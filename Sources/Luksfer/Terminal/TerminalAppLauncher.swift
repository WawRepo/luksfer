import AppKit
import LuksferCore

/// Opens a folder in an outside terminal app ("Open in Terminal app").
enum TerminalAppLauncher {
    enum LaunchError: LocalizedError {
        case notInstalled(TerminalApp)

        var errorDescription: String? {
            switch self {
            case .notInstalled(let app): return "\(app.displayName) is not installed."
            }
        }
    }

    /// The terminal apps on this Mac, in `TerminalApp.allCases` order.
    static func installedApps() -> [TerminalApp] {
        TerminalApp.allCases.filter { applicationURL(for: $0) != nil }
    }

    static func applicationURL(for app: TerminalApp) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
    }

    /// Opens `folder` in `app`: Terminal and iTerm2 open a new window there, Ghostty a new tab
    /// in its front window, Warp a new window through its `warp://` URL scheme.
    /// Throws when the app is not installed; a failure to open arrives in `completion`.
    static func open(_ folder: URL, in app: TerminalApp,
                     completion: ((Error?) -> Void)? = nil) throws {
        guard let appURL = applicationURL(for: app) else { throw LaunchError.notInstalled(app) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([app.launchURL(forFolder: folder)], withApplicationAt: appURL,
                                configuration: configuration) { _, error in
            DispatchQueue.main.async { completion?(error) }
        }
    }
}
