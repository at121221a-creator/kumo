import AVFoundation
import OSLog
import UIKit
import VideoToolbox

/// The video a user shares from an operation recording: their phone's screen, untouched
/// apart from speed, set inside a frame. Everything of ours goes on the outer layer:
/// the app's name and icon, the playback speed, the user's own request (unless they hide
/// it), a clock of the agent's working time, and the website. Nothing here is written
/// by a model; it is all known to the app.
enum PhoneRecordingExport {
    static let log = Logger(subsystem: "dsh.phone-recording", category: "export")
    private static let fps: Int32 = 30

    /// Where everything goes for a recording of this shape. An iPhone upright is tall
    /// (about 0.46 wide to 1 high); an iPad or an iPhone Duo upright is near 0.7; any of
    /// them turned sideways is wide. The canvas is always 1080 wide, which every feed takes,
    /// and only as tall as this screen needs: 9:16 for a phone, near 3:5 for an iPad,
    /// near square for a sideways screen.
    struct Layout {
        let canvas: CGSize
        let screen: CGRect
        let radius: CGFloat

        static let top: CGFloat = 308
        static let bottom: CGFloat = 176

        init(aspect: CGFloat) {
            let aspect = min(max(aspect, 0.3), 3)
            var width: CGFloat = 960
            var height = width / aspect
            if height > 1440 {
                height = 1440
                width = height * aspect
            }
            width = (width / 2).rounded() * 2
            height = (height / 2).rounded() * 2
            canvas = CGSize(width: 1080, height: Self.top + height + Self.bottom)
            screen = CGRect(x: ((canvas.width - width) / 2).rounded(), y: Self.top, width: width, height: height)
            // A phone's corners are deep; an iPad's (and a sideways screen's) are slight.
            radius = aspect < 0.6 ? width * 0.09 : min(width, height) * 0.035
        }
    }

    enum Failure: Error { case noVideo, writer }

    /// Renders to a new file in the temporary directory and returns it.
    static func render(source: URL, speed: Double, request: String?,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.noVideo }
        let duration = try await asset.load(.duration).seconds
        let natural = try await track.load(.naturalSize)
        let layout = Layout(aspect: natural.width / max(natural.height, 1))
        let size = layout.canvas

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fish Pocket \(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: output)

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000,
                                              AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.shouldOptimizeForNetworkUse = true

        guard reader.startReading(), writer.startWriting() else { throw Failure.writer }
        writer.startSession(atSourceTime: .zero)

        let chrome = Chrome(layout: layout, speed: speed, request: request)
        let step = 1.0 / Double(fps)
        var next = 0.0            // next output time to fill
        var last: CGImage?
        var written = 0.0

        func append(_ image: CGImage?, at time: Double, clock: Double, done: Bool) async throws {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { throw Failure.writer }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw Failure.writer }
            // A frame's drawing leaves autoreleased images behind; nothing drains them in this loop otherwise.
            autoreleasepool {
                chrome.draw(into: buffer, screenImage: image, clock: clock, done: done, total: duration)
            }
            if !adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600)) {
                throw writer.error ?? Failure.writer
            }
        }

        while let sample = readerOutput.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let source = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let out = source / speed
            guard out + step / 2 >= next else { continue }       // faster than the output rate: drop
            autoreleasepool {
                var image: CGImage?
                VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image)
                last = image ?? last
            }
            try await append(last, at: next, clock: source, done: false)
            written = next
            next = max(next + step, (out / step).rounded(.down) * step + step)
            progress(min(source / max(duration, 0.1), 1) * 0.95)
        }
        if reader.status == .failed { throw reader.error ?? Failure.writer }

        // Hold the last frame and show the total.
        var hold = written + step
        let end = hold + 1.5
        while hold < end {
            try await append(last, at: hold, clock: duration, done: true)
            hold += step
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure.writer }
        progress(1)
        return output
    }

    /// Everything around the screen; the static part is drawn once.
    private final class Chrome {
        let layout: Layout
        let background: CGImage
        var screen: CGRect { layout.screen }
        let font = UIFont.systemFont(ofSize: 30, weight: .semibold)

        init(layout: Layout, speed: Double, request: String?) {
            self.layout = layout
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: layout.canvas, format: format).image { ctx in
                Self.drawStatic(ctx.cgContext, layout: layout, speed: speed, request: request)
            }
            background = image.cgImage!
        }

        private static func drawStatic(_ cg: CGContext, layout: Layout, speed: Double, request: String?) {
            let size = layout.canvas
            let screen = layout.screen
            let colors = [UIColor(red: 14 / 255, green: 16 / 255, blue: 26 / 255, alpha: 1).cgColor,
                          UIColor(red: 30 / 255, green: 24 / 255, blue: 50 / 255, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

            // Shadow under the screen.
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 14), blur: 56, color: UIColor.black.withAlphaComponent(0.65).cgColor)
            cg.addPath(UIBezierPath(roundedRect: screen, cornerRadius: layout.radius).cgPath)
            cg.setFillColor(UIColor.black.cgColor)
            cg.fillPath()
            cg.restoreGState()

            // App icon and name.
            if let icon = Self.appIcon {
                let rect = CGRect(x: 60, y: 52, width: 56, height: 56)
                cg.saveGState()
                cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 12.6).cgPath)
                cg.clip()
                icon.draw(in: rect)
                cg.restoreGState()
            }
            draw("Fish Pocket", at: CGPoint(x: 132, y: 80), font: .systemFont(ofSize: 36, weight: .semibold), color: .white, anchor: .midLeft)

            let speedText = speed == 1 ? String(localized: "原速") : String(localized: "\(speed.formatted())× 播放")
            pill(cg, speedText, right: size.width - 60, y: 52, height: 56,
                 font: .systemFont(ofSize: 28, weight: .medium), text: UIColor(white: 0.88, alpha: 1),
                 fill: UIColor(white: 1, alpha: 0.12))

            if let request, !request.isEmpty {
                draw(String(localized: "我让 Agent："), at: CGPoint(x: 60, y: 148), font: .systemFont(ofSize: 30),
                     color: UIColor(white: 0.7, alpha: 1), anchor: .midLeft)
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byCharWrapping
                style.minimumLineHeight = 56
                style.maximumLineHeight = 56
                let text = NSAttributedString(string: request.replacingOccurrences(of: "\n", with: " "), attributes: [
                    .font: UIFont.systemFont(ofSize: 42, weight: .semibold), .foregroundColor: UIColor.white, .paragraphStyle: style,
                ])
                text.draw(with: CGRect(x: 60, y: 176, width: size.width - 120, height: 112),
                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            }

            draw(String(localized: "Agent 操控 \(UIDevice.current.model) 的实录 · fish.deepseek1024.com"), at: CGPoint(x: size.width / 2, y: size.height - 44),
                 font: .systemFont(ofSize: 26), color: UIColor(white: 1, alpha: 0.47), anchor: .center)
        }

        func draw(into buffer: CVPixelBuffer, screenImage: CGImage?, clock: Double, done: Bool, total: Double) {
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            let size = layout.canvas
            guard let cg = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                     bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return }
            // UIKit's top-left coordinates.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(cg)
            defer { UIGraphicsPopContext() }

            UIImage(cgImage: background).draw(at: .zero)
            if let screenImage {
                cg.saveGState()
                cg.addPath(UIBezierPath(roundedRect: screen, cornerRadius: layout.radius).cgPath)
                cg.clip()
                cg.interpolationQuality = .high
                UIImage(cgImage: screenImage).draw(in: screen)
                cg.restoreGState()
            }
            cg.addPath(UIBezierPath(roundedRect: screen.insetBy(dx: -3, dy: -3), cornerRadius: layout.radius + 3).cgPath)
            cg.setStrokeColor(UIColor(white: 1, alpha: 0.18).cgColor)
            cg.setLineWidth(3)
            cg.strokePath()

            let y = screen.maxY + 24
            if done {
                Self.pill(cg, String(localized: "完成 · 用时 \(Self.clock(total))"), right: screen.maxX, y: y, height: 60, font: font,
                          text: .white, fill: UIColor(red: 30 / 255, green: 160 / 255, blue: 90 / 255, alpha: 0.92))
            } else {
                let width = Self.pill(cg, "      " + String(localized: "Agent 操作中 \(Self.clock(clock))"), right: screen.maxX, y: y,
                                      height: 60, font: font, text: .white, fill: UIColor(white: 1, alpha: 0.11))
                cg.setFillColor(UIColor(red: 1, green: 0.27, blue: 0.27, alpha: 1).cgColor)
                cg.fillEllipse(in: CGRect(x: screen.maxX - width + 24, y: y + 22, width: 16, height: 16))
            }
        }

        /// The home-screen icon. "AppIcon" by name is not always loadable at run time; the
        /// bundle's own icon file is.
        static var appIcon: UIImage? {
            if let image = UIImage(named: "AppIcon") { return image }
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
            let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
            return (primary?["CFBundleIconFiles"] as? [String])?.last.flatMap { UIImage(named: $0) }
        }

        static func clock(_ seconds: Double) -> String {
            let s = max(Int(seconds), 0)
            return String(format: "%d:%02d", s / 60, s % 60)
        }

        enum Anchor { case midLeft, center }

        static func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor, anchor: Anchor) {
            let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            let bounds = string.size()
            let x = anchor == .center ? point.x - bounds.width / 2 : point.x
            string.draw(at: CGPoint(x: x, y: point.y - bounds.height / 2))
        }

        /// A capsule ending at `right`; returns its width.
        @discardableResult
        static func pill(_ cg: CGContext, _ text: String, right: CGFloat, y: CGFloat, height: CGFloat,
                         font: UIFont, text color: UIColor, fill: UIColor) -> CGFloat {
            let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            let width = string.size().width + 44
            let rect = CGRect(x: right - width, y: y, width: width, height: height)
            cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: height / 2).cgPath)
            cg.setFillColor(fill.cgColor)
            cg.fillPath()
            string.draw(at: CGPoint(x: rect.minX + 22, y: rect.midY - string.size().height / 2))
            return width
        }
    }
}
