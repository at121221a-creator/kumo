import Foundation

/// The apps 我的应用 starts with (MiniAppExamples in the bundle, one folder each): copied into
/// `~/apps` once, so they are the user's like any other. One the user deletes stays deleted, and
/// one added in a later version arrives with it.
enum MiniAppExamples {
    private static let offeredKey = "dsh.miniApps.examplesOffered"
    /// The examples actually copied in: an app of the user's own by an example's name was not.
    private static let installedKey = "dsh.miniApps.examplesInstalled"
    @MainActor private static var done = false

    /// The apps 小工具 marks as examples, so nobody takes them for a catalog of ours. Installs
    /// from before this was recorded fall back to what was offered.
    static var ids: Set<String> {
        let defaults = UserDefaults.standard
        return Set(defaults.stringArray(forKey: installedKey) ?? defaults.stringArray(forKey: offeredKey) ?? [])
    }

    @MainActor
    static func install() {
        guard !done else { return }
        done = true
        guard let source = Bundle.main.url(forResource: "MiniAppExamples", withExtension: nil) else { return }
        let files = FileManager.default
        var offered = Set(UserDefaults.standard.stringArray(forKey: offeredKey) ?? [])
        let ids = ((try? files.contentsOfDirectory(atPath: source.path)) ?? []).filter(MiniApp.validId).sorted()
        guard ids.contains(where: { !offered.contains($0) }) else { return }
        try? files.createDirectory(at: MiniAppStore.root, withIntermediateDirectories: true)
        var installed = self.ids
        for id in ids where !offered.contains(id) {
            let target = MiniAppStore.root.appending(path: id, directoryHint: .isDirectory)
            // An app of the user's own by that name stays as it is.
            if !files.fileExists(atPath: target.path),
               (try? files.copyItem(at: source.appending(path: id, directoryHint: .isDirectory), to: target)) != nil {
                installed.insert(id)
            }
            offered.insert(id)
        }
        UserDefaults.standard.set(offered.sorted(), forKey: offeredKey)
        UserDefaults.standard.set(installed.sorted(), forKey: installedKey)
    }
}
