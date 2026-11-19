import AVKit
import OSLog
import SwiftUI

/// Under a finished turn: what the agent did in other apps, recorded as it happened.
struct PhoneRecordingCards: View {
    let session: String
    let turn: Int
    @State private var open: PhoneRecorder.Recording?

    var body: some View {
        let items = PhoneRecorder.shared.recordings(session: session, turn: turn)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { recording in
                    Button { open = recording } label: { row(recording) }
                        .buttonStyle(.plain)
                }
            }
            .sheet(item: $open) { PhoneRecordingSheet(recording: $0) }
        }
    }

    private func row(_ recording: PhoneRecorder.Recording) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle").font(.body).foregroundStyle(Palette.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("操作录像").font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                Text("\(Duration.seconds(recording.duration).formatted(.time(pattern: .minuteSecond))) · 在其他 App 里的操作")
                    .font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("播放").font(.subheadline).foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.stroke))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(Text("播放操作录像"))
    }
}

/// The recording as it was, played at 2× by default: operating a phone is slow to watch.
struct PhoneRecordingSheet: View {
    let recording: PhoneRecorder.Recording
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false
    @State private var confirmingDelete = false

    static let defaultRate: Float = 2

    var body: some View {
        NavigationStack {
            RecordingPlayer(url: PhoneRecorder.url(of: recording))
                .ignoresSafeArea(edges: .bottom)
                .background(Color.black)
                .navigationTitle("操作录像")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(Text("关闭"))
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { sharing = true } label: { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel(Text("分享"))
                        Menu {
                            Button("删除录像", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }
                .confirmationDialog("删除这段录像？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("删除", role: .destructive) {
                        PhoneRecorder.shared.delete(recording)
                        dismiss()
                    }
                } message: {
                    Text("只删除录像，对话不受影响。")
                }
                .sheet(isPresented: $sharing) { PhoneRecordingShareSheet(recording: recording) }
        }
    }
}

private struct RecordingPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        player.defaultRate = PhoneRecordingSheet.defaultRate
        controller.player = player
        controller.speeds = [1, 2, 4, 8].map { rate in
            AVPlaybackSpeed(rate: rate, localizedName: String(localized: "\(rate.formatted())×"))
        }
        // The controls play at their own selected speed, not the player's default rate.
        if let fast = controller.speeds.first(where: { $0.rate == PhoneRecordingSheet.defaultRate }) {
            controller.selectSpeed(fast)
        }
        controller.allowsPictureInPicturePlayback = false
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
    }
}

/// Sharing puts the recording in our frame; the user picks the speed and whether their
/// own words appear on it.
struct PhoneRecordingShareSheet: View {
    let recording: PhoneRecorder.Recording
    @Environment(\.dismiss) private var dismiss
    @State private var speed: Double = 2
    @State private var showRequest = true
    @State private var progress: Double?
    @State private var failed = false
    @State private var job: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("播放速度", selection: $speed) {
                        ForEach([1.0, 2, 4, 8], id: \.self) { Text("\($0.formatted())×").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("播放速度")
                } footer: {
                    Text("分享出去的视频长 \(Duration.seconds(recording.duration / speed).formatted(.time(pattern: .minuteSecond)))。")
                }
                if let request = recording.request, !request.isEmpty {
                    Section {
                        Toggle("显示我的请求", isOn: $showRequest)
                    } footer: {
                        Text(showRequest ? "视频上方会显示：\(request)" : "视频上不显示你对 Agent 说了什么。")
                            .lineLimit(3)
                    }
                }
                Section {
                    Button {
                        export()
                    } label: {
                        HStack {
                            Text(progress == nil ? "生成视频并分享" : "正在生成…")
                            Spacer()
                            if let progress { ProgressView(value: progress).frame(width: 80) }
                        }
                    }
                    .disabled(progress != nil)
                } footer: {
                    Text("在这台手机上生成，画面外加上 Fish Pocket 的标识。录像没有声音。")
                }
            }
            .navigationTitle("分享录像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { job?.cancel(); dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("关闭"))
                }
            }
            .alert("没能生成视频", isPresented: $failed) {
                Button("好", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { job?.cancel() }
    }

    private func export() {
        progress = 0
        let source = PhoneRecorder.url(of: recording)
        let request = showRequest ? recording.request : nil
        let speed = speed
        job = Task {
            do {
                let file = try await Task.detached(priority: .userInitiated) {
                    try await PhoneRecordingExport.render(source: source, speed: speed, request: request) { value in
                        Task { @MainActor in progress = value }
                    }
                }.value
                progress = nil
                presentShareSheet([file])
            } catch is CancellationError {
                PhoneRecordingExport.log.notice("export cancelled")
                progress = nil
            } catch {
                PhoneRecordingExport.log.error("export failed: \(String(describing: error), privacy: .public)")
                progress = nil
                failed = true
            }
        }
    }
}
