import AppKit
import SwiftTerm

/// The terminal in the panel: SwiftTerm's local-process view with system colours, the system
/// monospaced font, and a callback for every key, paste or text the user sends.
///
/// SwiftTerm 1.99 sends keyboard input straight to the process, past `send(source:data:)`, and
/// its `keyDown` cannot be overridden from outside the module. So a local key monitor catches
/// key presses aimed at this view, and the `insertText` and `paste` overrides catch text that
/// arrives without a key press (dictation, the character viewer, Edit > Paste). Text Luksfer sends
/// with `send(txt:)` passes none of these, so it never counts as user input.
final class ShellTerminalView: LocalProcessTerminalView {
    /// The user typed, pasted or pressed a key here. Main thread.
    var onUserInput: (() -> Void)?

    private var keyMonitor: Any?
    private lazy var clipboardGuard = TerminalClipboardGuard(view: self)

    override init(frame: CGRect) {
        super.init(frame: frame,
                   font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                   options: TerminalOptions(scrollback: 10_000))
        terminalDelegate = clipboardGuard
        optionAsMetaKey = false
        applyTheme()
        setAccessibilityLabel("Terminal")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        onUserInput?()
        super.insertText(string, replacementRange: replacementRange)
    }

    override func paste(_ sender: Any) {
        onUserInput?()
        super.paste(sender)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        } else if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated { self?.noteKeyDown(event) }
                return event
            }
        }
    }

    /// Counts a key press as user input when it goes to this view. Command shortcuts go to the
    /// menus (copy, find...); Command-V reaches `paste(_:)`.
    func noteKeyDown(_ event: NSEvent) {
        guard event.type == .keyDown, let window, event.window === window,
              window.firstResponder === self,
              !event.modifierFlags.contains(.command)
        else { return }
        onUserInput?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    /// Resolves the theme for the current appearance and installs it.
    func applyTheme() {
        let theme = TerminalTheme.resolved(for: effectiveAppearance)
        // Foreground and background first: SwiftTerm derives its 256-colour palette from them.
        nativeForegroundColor = theme.foreground
        nativeBackgroundColor = theme.background
        installColors(theme.ansi)
        caretColor = theme.caret
        selectedTextBackgroundColor = theme.selection
        selectedTextForegroundColor = theme.foreground
        updateColorScheme(TerminalTheme.isDark(effectiveAppearance) ? .dark : .light)
    }
}

/// The terminal view's delegate. Text a program prints can ask for the clipboard (OSC 52): to set it
/// or to read it, with no prompt. `LocalProcessTerminalView` answers with the real clipboard in
/// methods a subclass cannot override, so this delegate refuses both and passes the rest on, like
/// Terminal.app, which has OSC 52 off. Copy and paste by the user do not come through here.
private final class TerminalClipboardGuard: TerminalViewDelegate {
    private unowned let view: LocalProcessTerminalView

    init(view: LocalProcessTerminalView) { self.view = view }

    func clipboardCopy(source: TerminalView, content: Data) {}
    func clipboardRead(source: TerminalView) -> Data? { nil }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        view.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }
    func setTerminalTitle(source: TerminalView, title: String) { view.setTerminalTitle(source: source, title: title) }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        view.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { view.send(source: source, data: data) }
    func scrolled(source: TerminalView, position: Double) { view.scrolled(source: source, position: position) }
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        view.requestOpenLink(source: source, link: link, params: params)
    }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) { view.rangeChanged(source: source, startY: startY, endY: endY) }
    func programStatusChanged(source: TerminalView, records: [TerminalProgramStatus]) {
        view.programStatusChanged(source: source, records: records)
    }
}
