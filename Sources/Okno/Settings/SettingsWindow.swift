import AppKit
import OknoCore
import SwiftUI

/// Settings (SwiftUI). Every value lives in Okno's own settings file.
struct SettingsView: View {
    @State private var keyMode = AppServices.shared.settings.keyMode
    @State private var showHidden = AppServices.shared.settings.showHidden
    @State private var follow = AppServices.shared.settings.terminalFollow
    @State private var terminalApp = TerminalApp(rawValue: AppServices.shared.settings.terminalApp) ?? .terminal
    private let installed = TerminalAppLauncher.installedApps()

    var body: some View {
        Form {
            Picker("Keys", selection: $keyMode) {
                Text("Windows: Enter opens, F2 renames").tag(KeyMode.windows)
                Text("Finder: Enter renames, ⌘↓ opens").tag(KeyMode.finder)
            }
            .onChange(of: keyMode) { _, v in AppServices.shared.update { $0.keyMode = v } }
            Toggle("Show hidden files", isOn: $showHidden)
                .onChange(of: showHidden) { _, v in AppServices.shared.update { $0.showHidden = v } }
            Section("Terminal") {
                Picker("Open in Terminal app uses", selection: $terminalApp) {
                    ForEach(TerminalApp.allCases, id: \.self) { app in
                        Text(app.displayName + (installed.contains(app) ? "" : " (not installed)")).tag(app)
                    }
                }
                .onChange(of: terminalApp) { _, v in AppServices.shared.update { $0.terminalApp = v.rawValue } }
                Toggle("Follow: the terminal and the active pane stay in the same folder", isOn: $follow)
                    .onChange(of: follow) { _, v in AppServices.shared.update { $0.terminalFollow = v } }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize()
    }
}

enum SettingsWindow {
    static func make() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Okno Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        return window
    }
}
