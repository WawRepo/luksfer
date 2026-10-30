import AppKit

/// One folder suggestion: folder icon and path. Highlights on hover and with ↑ ↓.
final class PathSuggestionRow: NSView {
    var onPick: (() -> Void)?
    var onHover: (() -> Void)?
    var isHighlighted = false { didSet { updateColors() } }

    private let icon = NSImageView(image: PathBarView.folderIcon)
    private let label: NSTextField

    init(path: String) {
        label = NSTextField(labelWithString: path)
        super.init(frame: .zero)
        label.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        label.lineBreakMode = .byTruncatingHead
        addSubview(icon)
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(path)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 8, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let labelHeight = label.intrinsicContentSize.height
        label.frame = NSRect(x: 32, y: (bounds.height - labelHeight) / 2,
                             width: max(0, bounds.width - 40), height: labelHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseMoved(with event: NSEvent) { if !isHighlighted { onHover?() } }
    override func mouseDown(with event: NSEvent) { onPick?() }
    override func accessibilityPerformPress() -> Bool { onPick?(); return true }

    private func updateColors() {
        label.textColor = isHighlighted ? .alternateSelectedControlTextColor : .labelColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }
}

/// The error line: a red mark and the message, in red.
final class PathErrorRow: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    var message: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        icon.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "Error")?
            .withSymbolConfiguration(config)
        icon.contentTintColor = .systemRed
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = .systemRed
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(icon)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 8, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let labelHeight = label.intrinsicContentSize.height
        label.frame = NSRect(x: 32, y: (bounds.height - labelHeight) / 2,
                             width: max(0, bounds.width - 40), height: labelHeight)
    }
}
