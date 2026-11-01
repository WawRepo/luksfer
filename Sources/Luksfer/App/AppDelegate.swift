import AppKit
import LuksferCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [BrowserWindowController] = []
    private var settingsWindow: NSWindow?
    private var terminating = false
    private lazy var hotKey = GlobalHotKey { [weak self] in self?.newWindowFromHotKey() }
    /// Started at login: no window until the user asks for one (⌥⌘Space, the Dock).
    private var quietLaunch = false

    // Before a launch's open request (`application(_:open:)`), which lists a folder.
    func applicationWillFinishLaunching(_ notification: Notification) {
        DatalessPolicy.protectProcess()
        NSApp.mainMenu = MainMenu.build()
        quietLaunch = Self.launchedAtLogin()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let states = AppServices.shared.settings.windows
        quietLaunch = quietLaunch || Self.launchedAtLogin()
        if let open = DevHooks.openFolder {
            openWindow(state: nil, folder: open)
        } else if controllers.isEmpty && !quietLaunch {
            // Not launched to open a folder (that window is open already): bring back the saved windows.
            if states.isEmpty { openWindow(state: nil) } else { states.forEach { openWindow(state: $0) } }
        }
        updateHotKey()
        if !quietLaunch { NSApp.activate() }
        DevHooks.scheduleSnapshot()
        DevHooks.scheduleBench()
        SelfTest.scheduleIfAsked()
    }

    @discardableResult
    func openWindow(state: WindowState?, folder: URL? = nil) -> BrowserWindowController {
        let c = BrowserWindowController(state: state, folder: folder)
        c.onClose = { [weak self] closed in self?.windowClosed(closed) }
        controllers.append(c)
        if state == nil, let window = c.window { stepFromFrontWindow(window) }
        c.showWindow(nil)
        return c
    }

    /// A new window sits 24 points down and right of the front window, so it never covers it exactly.
    /// It goes back to the top left of the screen when it would leave the screen.
    private func stepFromFrontWindow(_ window: NSWindow) {
        guard let front = NSApp.orderedWindows.first(where: {
            $0 !== window && $0.isVisible && $0.windowController is BrowserWindowController
        }) else { return }
        var topLeft = NSPoint(x: front.frame.minX + 24, y: front.frame.maxY - 24)
        if let visible = front.screen?.visibleFrame,
           topLeft.x + window.frame.width > visible.maxX || topLeft.y - window.frame.height < visible.minY {
            topLeft = NSPoint(x: visible.minX, y: visible.maxY)
        }
        window.setFrameTopLeftPoint(topLeft)
    }

    private static func launchedAtLogin() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    /// Turns ⌥⌘Space on or off to match Settings. The self-test never takes the key from the user.
    func updateHotKey() {
        if AppServices.shared.settings.newWindowHotKey && !SelfTest.isRunning { hotKey.register() } else { hotKey.unregister() }
    }

    /// ⌥⌘Space from any app, like Win+E: a new single-pane window in Downloads, in front.
    func newWindowFromHotKey() {
        quietLaunch = false
        let c = openWindow(state: nil)
        NSApp.activate()
        c.window?.makeKeyAndOrderFront(nil)
    }

    @objc func newWindow(_ sender: Any?) {
        let current = (NSApp.keyWindow?.windowController as? BrowserWindowController)?.activePane.folder
        openWindow(state: nil, folder: current)
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

    /// While ⌥⌘Space is on, Luksfer keeps running without a window, so the key keeps working.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppServices.shared.settings.newWindowHotKey
    }

    /// Luksfer came to the front (a keyboard shortcut, ⌘Tab, the Dock) with no window on screen.
    func applicationDidBecomeActive(_ notification: Notification) {
        // A moment later: a hidden app shows its windows again only after it became active, and a
        // shortcut that opens a folder (`open -a Luksfer ~/Downloads`) sends its request just after.
        guard !quietLaunch else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.showWindowIfNoneOnScreen() }
    }

    /// The Dock icon was clicked or the app was opened again while it runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        quietLaunch = false
        showWindowIfNoneOnScreen()
        return false
    }

    /// Like Windows: bring the minimized windows back, or open a new window when there is none.
    func showWindowIfNoneOnScreen() {
        guard !terminating, !NSApp.isHidden,
              !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        let minimized = NSApp.windows.filter(\.isMiniaturized)
        if !minimized.isEmpty {
            minimized.forEach { $0.deminiaturize(nil) }
        } else if controllers.isEmpty {
            openWindow(state: nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminating = true
        // With no window open, the last closed window's state (saved when it closed) stays.
        if !controllers.isEmpty { saveWindows() }
        return .terminateNow
    }

    /// Folders dropped on the Dock icon or opened with Luksfer (a shortcut that runs
    /// `open -a Luksfer ~/Downloads`) open in a new single-pane window.
    func application(_ application: NSApplication, open urls: [URL]) {
        quietLaunch = false
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
