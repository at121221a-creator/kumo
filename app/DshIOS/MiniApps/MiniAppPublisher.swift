import CryptoKit
import Foundation

/// An app has two states. What the agent writes in `~/apps/<id>` is the working copy: the agent's
/// browser shows it, compiled as it is asked for. What the user opens is the published copy in
/// `.build` beside it: every file, JSX and TypeScript already compiled, so opening an app never
/// compiles, and nothing the system may clear (the caches) is needed to open it.
///
/// An app is published when the agent's turn ends, when the list of apps is read, and, the
/// first time, when it is opened. While an agent works, an app opens as last published: a half
/// written one is never shown. The copy before is kept in `.build-previous`.
actor MiniAppPublisher {
    static let shared = MiniAppPublisher()

    static let buildFolder = ".build"
    static let previousFolder = ".build-previous"
    private static let manifest = "build.json"

    /// Set from the session list: an agent of this phone is working, maybe on an app.
    @MainActor static var agentBusy = false

    private var running: [String: Task<Bool, Never>] = [:]

    /// Publishes `app` unless its published copy is of the files as they are now. True when
    /// there is a published copy afterwards.
    @discardableResult
    func publish(_ app: MiniApp) async -> Bool {
        if let task = running[app.id] { return await task.value }
        let folder = app.folder
        let task = Task.detached(priority: .userInitiated) { Self.build(folder) }
        running[app.id] = task
        let built = await task.value
        running[app.id] = nil
        return built
    }

    /// Before opening `app`: its published copy, made now if there is none or it is out of
    /// date, unless an agent is working and an older one exists.
    func prepare(_ app: MiniApp, agentBusy: Bool) async {
        let published = Self.published(app.folder)
        if published != nil, agentBusy || published == Self.fingerprint(app.folder) { return }
        await publish(app)
    }

    /// The folder the user's copy is served from.
    nonisolated static func served(_ folder: URL) -> URL? {
        let build = folder.appending(path: buildFolder, directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: build.appending(path: manifest).path) ? build : nil
    }

    // MARK: Building

    /// The fingerprint the published copy was made from, if there is one.
    private nonisolated static func published(_ folder: URL) -> String? {
        let file = folder.appending(path: buildFolder).appending(path: manifest)
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["fingerprint"] as? String
    }

    /// The working copy's files, by path, size and date, and the compiler: what a published copy
    /// is current against. Cheap enough for every opening.
    nonisolated static func fingerprint(_ folder: URL) -> String {
        var lines = [MiniAppCompiler.version]
        for (path, file) in sources(folder) {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            lines.append("\(path)\t\(values?.fileSize ?? 0)\t\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        return SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Every file of the working copy, by its path in it; hidden ones (the published copies) left out.
    private nonisolated static func sources(_ folder: URL) -> [(String, URL)] {
        let base = folder.resolvingSymlinksInPath().standardizedFileURL
        guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles) else { return [] }
        var found: [(String, URL)] = []
        while let file = files.nextObject() as? URL {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let path = String(file.resolvingSymlinksInPath().standardizedFileURL.path.dropFirst(base.path.count + 1))
            guard !path.isEmpty, !path.hasPrefix("..") else { continue }
            found.append((path, file))
        }
        return found.sorted { $0.0 < $1.0 }
    }

    /// Writes a new published copy beside the old one and swaps them; the old becomes the previous.
    private nonisolated static func build(_ folder: URL) -> Bool {
        let fingerprint = fingerprint(folder)
        if published(folder) == fingerprint { return true }
        let files = FileManager.default
        let staging = folder.appending(path: ".build-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? files.removeItem(at: staging) }
        do {
            try files.createDirectory(at: staging, withIntermediateDirectories: true)
            for (path, file) in sources(folder) {
                let target = staging.appending(path: path)
                try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let ext = file.pathExtension.lowercased()
                if ["jsx", "tsx", "ts", "js"].contains(ext), !file.lastPathComponent.hasSuffix(".min.js"),
                   let source = try? String(contentsOf: file, encoding: .utf8) {
                    try Data(MiniAppCompiler.shared.module(source, file: file.lastPathComponent).utf8).write(to: target)
                } else {
                    try files.copyItem(at: file, to: target)
                }
            }
            let info: [String: Any] = ["fingerprint": fingerprint, "compiler": MiniAppCompiler.version, "builtAt": Date.now.timeIntervalSince1970]
            try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]).write(to: staging.appending(path: manifest))

            let current = folder.appending(path: buildFolder, directoryHint: .isDirectory)
            let previous = folder.appending(path: previousFolder, directoryHint: .isDirectory)
            if files.fileExists(atPath: current.path) {
                try? files.removeItem(at: previous)
                try files.moveItem(at: current, to: previous)
            }
            try files.moveItem(at: staging, to: current)
            return true
        } catch {
            return served(folder) != nil
        }
    }
}
