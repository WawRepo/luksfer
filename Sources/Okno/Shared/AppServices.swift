import AppKit
import OknoCore

extension Notification.Name {
    /// Favorites, hidden files or another shared setting changed.
    static let oknoSettingsChanged = Notification.Name("OknoSettingsChanged")
}

/// Things every window shares.
final class AppServices {
    static let shared = AppServices()

    /// `OKNO_SETTINGS_DIR` points test runs at a sandbox, so they never touch the real settings.
    let store = SettingsStore(folder: ProcessInfo.processInfo.environment["OKNO_SETTINGS_DIR"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? SettingsStore.defaultFolder)
    /// One undo history for all windows, like Explorer: file changes are not per window.
    let undoManager = UndoManager()
    var settings: AppSettings { store.settings }

    func update(_ change: (inout AppSettings) -> Void) {
        let before = store.settings
        store.update(change)
        if before.favorites != store.settings.favorites || before.showHidden != store.settings.showHidden
            || before.keyMode != store.settings.keyMode || before.terminalApp != store.settings.terminalApp {
            NotificationCenter.default.post(name: .oknoSettingsChanged, object: nil)
        }
    }

    // MARK: Favorites

    func isFavorite(_ url: URL) -> Bool {
        settings.favorites.contains { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }
    }

    func pin(_ urls: [URL], at index: Int? = nil) {
        update { s in
            var i = min(index ?? s.favorites.count, s.favorites.count)
            for url in urls where !s.favorites.contains(where: { $0.path == url.standardizedFileURL.path }) {
                s.favorites.insert(Favorite(path: url.standardizedFileURL.path, label: url.lastPathComponent), at: i)
                i += 1
            }
        }
    }

    func unpin(_ url: URL) {
        update { $0.favorites.removeAll { $0.path == url.standardizedFileURL.path } }
    }
}

/// Turns off downloading of cloud-only files for the whole process, so nothing Okno does by
/// itself (listing, icons, previews of metadata) can start a download. The file operation engine
/// turns it back on, per thread, while it copies a file the user chose.
enum DatalessPolicy {
    static func protectProcess() {
        let r = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        if r != 0 { NSLog("Okno: could not set the dataless policy (errno \(errno))") }
    }
}
