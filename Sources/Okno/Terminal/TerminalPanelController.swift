import AppKit
import OknoCore
import SwiftTerm

/// The terminal panel at the bottom of the window: a header strip and the user's login shell.
///
/// The shell starts at the first layout that gives the terminal a usable size. With zsh, Okno's
/// startup files (`ZshIntegration`) report the folder and the prompt; other shells run without
/// them, so `changeDirectory(to:)` never types into them.
final class TerminalPanelController: NSViewController {
    weak var delegate: TerminalPanelDelegate?

    /// The header's Follow checkbox. Setting it does not call the delegate.
    var followEnabled = true {
        didSet { header.follow = followEnabled }
    }

    /// The last folder the shell reported (OSC 7).
    private(set) var currentFolder: URL?

    /// The shell waits at its prompt and nothing was typed since.
    var isAtIdlePrompt: Bool { isShellRunning && session.isIdle }

    /// A shell runs in the panel.
    private(set) var isShellRunning = false

    private let startFolder: URL
    private let shellFilesFolder: URL
    private let header = TerminalPanelHeader()
    private let terminalBox = TerminalBackgroundView()
    private var terminalView: ShellTerminalView?
    private var oscObservation: TerminalOscObservation?
    private var session = ShellSessionState()
    private var pendingStart: URL?
    private var focusAfterStart = false
    /// For `deinit`, which cannot reach main-actor state.
    nonisolated(unsafe) private var runningProcess: LocalProcess?

    /// - Parameters:
    ///   - startFolder: the folder the first shell starts in.
    ///   - shellFilesFolder: where the zsh integration files go (the app passes
    ///     `~/Library/Application Support/Okno/shell/`).
    init(startFolder: URL, shellFilesFolder: URL) {
        self.startFolder = startFolder
        self.shellFilesFolder = shellFilesFolder
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let process = runningProcess, process.running { kill(process.shellPid, SIGHUP) }
    }

    override func loadView() {
        let root = NSView()
        root.setAccessibilityElement(true)
        root.setAccessibilityRole(.group)
        root.setAccessibilityLabel("Terminal panel")
        for part in [header, terminalBox] as [NSView] {
            part.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(part)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            terminalBox.topAnchor.constraint(equalTo: header.bottomAnchor),
            terminalBox.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            terminalBox.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            terminalBox.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        header.follow = followEnabled
        header.onFollowChanged = { [weak self] enabled in
            guard let self else { return }
            followEnabled = enabled
            delegate?.terminalPanel(self, didSetFollow: enabled)
        }
        header.onOpenInTerminalApp = { [weak self] in
            guard let self else { return }
            delegate?.terminalPanelOpenInTerminalApp(self)
        }
        header.onClose = { [weak self] in
            guard let self else { return }
            delegate?.terminalPanelWantsClose(self)
        }
        view = root
        pendingStart = startFolder
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        startIfPending()
    }

    /// Types ` builtin cd -- '<path>'` and Return when the shell waits at an empty prompt and is
    /// elsewhere. Returns whether it typed, or will type right after a `cd` it typed before that
    /// still runs. Does not check `followEnabled`.
    @discardableResult
    func changeDirectory(to folder: URL) -> Bool {
        guard isShellRunning, let terminalView else { return false }
        switch session.request(folder) {
        case .send(let line):
            terminalView.send(txt: line)
            return true
        case .queued:
            return true
        case .alreadyThere, .busy:
            return false
        }
    }

    /// Types `text` into the shell as if pasted (the self-test uses it).
    func type(_ text: String) {
        terminalView?.send(txt: text)
    }

    /// Moves keyboard focus to the terminal (after the shell starts, if it has not yet).
    func focusTerminal() {
        _ = view
        guard let terminalView else {
            focusAfterStart = true
            return
        }
        view.window?.makeFirstResponder(terminalView)
    }

    /// Starts a new shell in `folder` on a clean screen. Ends the old shell if it still runs.
    func restartShell(in folder: URL) {
        _ = view
        let hadFocus = terminalView.map { view.window?.firstResponder === $0 } ?? false
        terminateShell()
        pendingStart = folder
        focusAfterStart = focusAfterStart || hadFocus
        startIfPending()
    }

    /// Hangs up the shell (SIGHUP, as when a terminal window closes). The delegate then gets
    /// `terminalPanelShellDidExit`.
    func terminateShell() {
        guard isShellRunning, let process = terminalView?.process, process.running else { return }
        kill(process.shellPid, SIGHUP)
    }

    // MARK: - Shell

    private func startIfPending() {
        guard let folder = pendingStart,
              terminalBox.bounds.width >= 100, terminalBox.bounds.height >= 30
        else { return }
        pendingStart = nil
        startShell(in: folder)
    }

    private func startShell(in folder: URL) {
        terminalView?.removeFromSuperview()
        oscObservation = nil
        session.reset()
        currentFolder = nil
        header.setFolder(nil)

        // A small margin left and above; the scroller keeps the right edge.
        let bounds = terminalBox.bounds
        let terminal = ShellTerminalView(frame: NSRect(x: 6, y: 2, width: bounds.width - 6,
                                                       height: bounds.height - 6))
        terminal.autoresizingMask = [.width, .height]
        terminal.processDelegate = self
        terminal.onUserInput = { [weak self] in self?.session.userInput() }
        terminalBox.addSubview(terminal)
        terminalView = terminal
        oscObservation = observeShell(terminal)

        let plan = launchPlan()
        var isFolder: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder)
        terminal.startProcess(executable: plan.executable, args: [], environment: plan.environment,
                              execName: plan.argv0,
                              currentDirectory: exists && isFolder.boolValue ? folder.path : NSHomeDirectory())
        runningProcess = terminal.process
        isShellRunning = true
        if focusAfterStart {
            focusAfterStart = false
            view.window?.makeFirstResponder(terminal)
        }
    }

    /// OSC 7 and the prompt marks, read from one ordered stream so a folder never overtakes
    /// the prompt that follows it.
    private func observeShell(_ terminal: ShellTerminalView) -> TerminalOscObservation {
        terminal.observeOscEvents { [weak self, weak terminal] event in
            guard event.code == 7 || event.code == ZshIntegration.markCode else { return }
            let code = event.code
            let payload = String(decoding: event.payload, as: UTF8.self)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let terminal, terminal === self.terminalView else { return }
                    self.handleOsc(code: code, payload: payload)
                }
            }
        }
    }

    private func handleOsc(code: Int, payload: String) {
        if code == ZshIntegration.markCode {
            guard let mark = ShellMark(payload: payload) else { return }
            if let line = session.received(mark) { terminalView?.send(txt: line) }
            return
        }
        guard let host = OSC7.host(fromPayload: payload),
              OSC7.isLocal(host: host, localHostName: Self.localHostName),
              let folder = OSC7.folder(fromPayload: payload),
              let change = session.reported(folder: folder)
        else { return }
        switch change {
        case .own(let url):
            currentFolder = url
            header.setFolder(url)
        case .user(let url):
            currentFolder = url
            header.setFolder(url)
            delegate?.terminalPanel(self, didChangeDirectory: url)
        }
    }

    private func launchPlan() -> ShellLaunchPlan {
        let account = getpwuid(getuid())
        let accountShell = account.flatMap { $0.pointee.pw_shell }.map { String(cString: $0) }
        return ShellLaunchPlan.make(
            accountShell: accountShell,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
            base: Terminal.getEnvironmentVariables(termName: "xterm-256color"),
            processEnvironment: ProcessInfo.processInfo.environment,
            home: NSHomeDirectory(),
            user: NSUserName(),
            shellFilesFolder: writeZshFiles() ? shellFilesFolder.path : nil)
    }

    /// Writes the zsh integration files where they differ. False when it cannot: the shell then
    /// starts without them rather than without the user's own startup files.
    private func writeZshFiles() -> Bool {
        do {
            try FileManager.default.createDirectory(at: shellFilesFolder, withIntermediateDirectories: true)
            for (name, text) in ZshIntegration.files() {
                let url = shellFilesFolder.appendingPathComponent(name)
                if (try? String(contentsOf: url, encoding: .utf8)) == text { continue }
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
            return true
        } catch {
            return false
        }
    }

    private static let localHostName: String = {
        var buffer = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        return gethostname(&buffer, buffer.count) == 0 ? String(cString: buffer) : ""
    }()
}

extension TerminalPanelController: LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    /// Unused: OSC 7 is read with the prompt marks in `observeShell`, in order.
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard source === terminalView else { return }
        shellStopped()
        terminalView?.feed(text: "\r\n\u{1B}[2m[Process completed]\u{1B}[0m\r\n")
        delegate?.terminalPanelShellDidExit(self)
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        guard source === terminalView else { return }
        shellStopped()
    }

    private func shellStopped() {
        isShellRunning = false
        runningProcess = nil
        session.reset()
    }
}

/// Fills the terminal's margin with the terminal's own background colour.
private final class TerminalBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.intersection(bounds).fill()
    }
}
