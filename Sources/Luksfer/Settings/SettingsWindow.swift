import AppKit
import LuksferCore
import ServiceManagement
import SwiftUI

/// Settings (SwiftUI). Every value lives in Luksfer's own settings file.
struct SettingsView: View {
    @State private var keyMode = AppServices.shared.settings.keyMode
    @State private var showHidden = AppServices.shared.settings.showHidden
    @State private var follow = AppServices.shared.settings.terminalFollow
    @State private var terminalApp = TerminalApp(rawValue: AppServices.shared.settings.terminalApp) ?? .terminal
    @State private var hotKey = AppServices.shared.settings.newWindowHotKey
    // macOS keeps the login item, not the settings file.
    @State private var atLogin = SMAppService.mainApp.status == .enabled
    @State private var loginNote: String?
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
            Section("New window from any app") {
                Toggle("⌥⌘Space opens a new window in Downloads", isOn: $hotKey)
                    .onChange(of: hotKey) { _, v in
                        AppServices.shared.update { $0.newWindowHotKey = v }
                        (NSApp.delegate as? AppDelegate)?.updateHotKey()
                    }
                Toggle("Open Luksfer at login", isOn: $atLogin)
                    .onChange(of: atLogin) { _, v in setOpenAtLogin(v) }
                Text(loginNote ?? "Luksfer keeps running when you close its last window, so the key works. If nothing happens, turn off \"Show Finder search window\" in System Settings > Keyboard > Keyboard Shortcuts > Spotlight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private func setOpenAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        guard on != (service.status == .enabled) else { return }
        do {
            if on { try service.register() } else { try service.unregister() }
            loginNote = service.status == .requiresApproval
                ? "Allow Luksfer in System Settings > General > Login Items." : nil
        } catch {
            loginNote = "Luksfer could not change the login item: \(error.localizedDescription)"
        }
        atLogin = service.status == .enabled
    }
}

enum SettingsWindow {
    static func make() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Luksfer Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        return window
    }
}
