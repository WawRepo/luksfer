import AppKit
import OknoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [BrowserWindowController] = []
    private var settingsWindow: NSWindow?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        DatalessPolicy.protectProcess()
        NSApp.mainMenu = MainMenu.build()
        let states = AppServices.shared.settings.windows
        if let open = DevHooks.openFolder {
            openWindow(state: nil, folder: open)
        } else if states.isEmpty {
            openWindow(state: nil)
        } else {
            states.forEach { openWindow(state: $0) }
        }
        NSApp.activate()
        DevHooks.scheduleSnapshot()
        DevHooks.scheduleBench()
    }

    @discardableResult
    func openWindow(state: WindowState?, folder: URL? = nil) -> BrowserWindowController {
        let c = BrowserWindowController(state: state, folder: folder)
        c.onClose = { [weak self] closed in self?.windowClosed(closed) }
        controllers.append(c)
        c.showWindow(nil)
        return c
    }

    @objc func newWindow(_ sender: Any?) {
        let current = (NSApp.keyWindow?.windowController as? BrowserWindowController)?.activePane.folder
        let c = openWindow(state: nil, folder: current)
        if let frame = NSApp.keyWindow?.frame, c.window !== NSApp.keyWindow {
            c.window?.setFrameTopLeftPoint(NSPoint(x: frame.minX + 24, y: frame.maxY - 24))
        }
    }

    private func windowClosed(_ c: BrowserWindowController) {
        // The last window's state is what the next launch restores.
        if controllers.count == 1 && !terminating { saveWindows() }
        controllers.removeAll { $0 === c }
    }

    private func saveWindows() {
        let states = controllers.map { $0.state() }
        AppServices.shared.update { $0.windows = states }
        AppServices.shared.store.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminating = true
        saveWindows()
        return .terminateNow
    }

    /// Folders dropped on the Dock icon or opened with Okno open in a new window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            let c = openWindow(state: nil, folder: isDir.boolValue ? url : url.deletingLastPathComponent())
            if !isDir.boolValue { c.activePane.list.reload(select: [url]) }
        }
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil { settingsWindow = SettingsWindow.make() }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
