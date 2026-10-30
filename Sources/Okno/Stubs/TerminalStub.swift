import AppKit

// Temporary stand-in until the terminal branch is merged. Same API.
protocol TerminalPanelDelegate: AnyObject {
    func terminalPanel(_ panel: TerminalPanelController, didChangeDirectory folder: URL)
    func terminalPanelShellDidExit(_ panel: TerminalPanelController)
    func terminalPanelWantsClose(_ panel: TerminalPanelController)
    func terminalPanelOpenInTerminalApp(_ panel: TerminalPanelController)
    func terminalPanel(_ panel: TerminalPanelController, didSetFollow enabled: Bool)
}

final class TerminalPanelController: NSViewController {
    weak var delegate: TerminalPanelDelegate?
    var followEnabled = true
    private(set) var currentFolder: URL?
    private(set) var isAtIdlePrompt = false
    init(startFolder: URL, shellFilesFolder: URL) { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() { view = NSView() }
    @discardableResult func changeDirectory(to folder: URL) -> Bool { false }
    func focusTerminal() {}
    func restartShell(in folder: URL) {}
}

enum TerminalApp: String, CaseIterable, Codable {
    case terminal, iterm2, ghostty, warp
    var displayName: String { rawValue }
}

enum TerminalAppLauncher {
    static func installedApps() -> [TerminalApp] { [.terminal] }
    static func open(_ folder: URL, in app: TerminalApp) throws {}
}
