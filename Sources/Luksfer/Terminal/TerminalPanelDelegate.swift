import Foundation

/// What the terminal panel tells its host. Every call comes on the main thread.
@MainActor
protocol TerminalPanelDelegate: AnyObject {
    /// The user moved the shell to another folder (OSC 7), repeats removed. Folders reached by
    /// the panel's own `changeDirectory(to:)` are not reported back: the host is there already.
    /// The panel does not check `followEnabled`; the host does before it moves a pane.
    func terminalPanel(_ panel: TerminalPanelController, didChangeDirectory folder: URL)
    /// The shell exited (e.g. the user typed `exit`). The host usually hides the panel.
    func terminalPanelShellDidExit(_ panel: TerminalPanelController)
    /// The header's close button.
    func terminalPanelWantsClose(_ panel: TerminalPanelController)
    /// The header's "Open in Terminal app" button.
    func terminalPanelOpenInTerminalApp(_ panel: TerminalPanelController)
    /// The Follow checkbox changed (the host saves the setting).
    func terminalPanel(_ panel: TerminalPanelController, didSetFollow enabled: Bool)
}
