import AppKit

/// The list that hangs under the path bar while typing: folder suggestions or an error message,
/// with a hint line at the bottom. It lives in a borderless child window that never takes focus,
/// so the text field keeps the keyboard.
final class PathPopup {
    /// A suggestion row was clicked.
    var onPick: ((Int) -> Void)?
    /// The mouse moved over a row.
    var onHover: ((Int) -> Void)?

    let content = PathPopupContentView()
    private var panel: PathPopupPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    init() {
        content.onPick = { [weak self] index in self?.onPick?(index) }
        content.onHover = { [weak self] index in self?.onHover?(index) }
    }

    func show(suggestions: [String], highlighted: Int?, below bar: NSView) {
        content.showSuggestions(suggestions, highlighted: highlighted)
        present(below: bar)
    }

    func show(error message: String, below bar: NSView) {
        content.showError(message)
        present(below: bar)
    }

    func setHighlighted(_ index: Int?) {
        content.highlighted = index
    }

    func close() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// Moves the list under the bar again (after the window or the bar changed size).
    func reposition(below bar: NSView) {
        guard isVisible else { return }
        present(below: bar)
    }

    private func present(below bar: NSView) {
        guard let window = bar.window else { return }
        let width = bar.bounds.width
        content.width = width
        let height = content.fittingHeight
        let barOnScreen = window.convertToScreen(bar.convert(bar.bounds, to: nil))
        let frame = NSRect(x: barOnScreen.minX, y: barOnScreen.minY - 3 - height, width: width, height: height)

        let panel = self.panel ?? makePanel()
        panel.appearance = window.effectiveAppearance
        panel.setFrame(frame, display: false)
        content.frame = NSRect(origin: .zero, size: frame.size)
        content.needsLayout = true
        content.needsDisplay = true
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        panel.invalidateShadow()
    }

    private func makePanel() -> PathPopupPanel {
        let panel = PathPopupPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = content
        self.panel = panel
        return panel
    }
}

/// A panel that never becomes key or main, so typing stays in the path bar.
final class PathPopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The popup's content: rows of folders (or one error line) and the hint line.
final class PathPopupContentView: NSView {
    static let hint = "Tab completes · Enter goes · Esc cancels · type “term” for a terminal here"
    static let rowHeight: CGFloat = 26
    static let padding: CGFloat = 4
    static let footerHeight: CGFloat = 24

    var onPick: ((Int) -> Void)?
    var onHover: ((Int) -> Void)?
    var width: CGFloat = 300

    var highlighted: Int? {
        didSet { rows.enumerated().forEach { $0.element.isHighlighted = $0.offset == highlighted } }
    }

    private var rows: [PathSuggestionRow] = []
    private let errorRow = PathErrorRow()
    private let footer = NSTextField(labelWithString: PathPopupContentView.hint)
    private var showsError = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        footer.font = .systemFont(ofSize: 11.5)
        footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byTruncatingTail
        errorRow.isHidden = true
        addSubview(footer)
        addSubview(errorRow)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Folder suggestions")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func showSuggestions(_ paths: [String], highlighted: Int?) {
        showsError = false
        errorRow.isHidden = true
        rows.forEach { $0.removeFromSuperview() }
        rows = paths.enumerated().map { index, path in
            let row = PathSuggestionRow(path: path)
            row.onPick = { [weak self] in self?.onPick?(index) }
            row.onHover = { [weak self] in self?.onHover?(index) }
            addSubview(row)
            return row
        }
        self.highlighted = highlighted
        setAccessibilityLabel("Folder suggestions")
        needsLayout = true
    }

    func showError(_ message: String) {
        showsError = true
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        errorRow.message = message
        errorRow.isHidden = false
        setAccessibilityLabel(message)
        needsLayout = true
    }

    var fittingHeight: CGFloat {
        let body = showsError ? Self.rowHeight + 4 : CGFloat(rows.count) * Self.rowHeight
        return Self.padding + body + Self.footerHeight + Self.padding / 2
    }

    override func layout() {
        super.layout()
        // Not insetBy: on a zero-size view it returns a rect at infinity.
        let inner = NSRect(x: Self.padding, y: 0, width: max(0, bounds.width - 2 * Self.padding),
                           height: bounds.height)
        var y = Self.padding
        if showsError {
            errorRow.frame = NSRect(x: inner.minX, y: y, width: inner.width, height: Self.rowHeight + 4)
            y += Self.rowHeight + 4
        }
        for row in rows {
            row.frame = NSRect(x: inner.minX, y: y, width: inner.width, height: Self.rowHeight)
            y += Self.rowHeight
        }
        let footerY = y + (Self.footerHeight - footer.intrinsicContentSize.height) / 2 + 1
        footer.frame = NSRect(x: inner.minX + 8, y: footerY, width: max(0, inner.width - 16),
                              height: footer.intrinsicContentSize.height)
        separatorY = y + 0.5
    }

    private var separatorY: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 2, bounds.height > 2 else { return }
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.textBackgroundColor.setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()
        NSColor.separatorColor.setFill()
        NSRect(x: Self.padding, y: separatorY, width: bounds.width - 2 * Self.padding, height: 1).fill()
    }
}
