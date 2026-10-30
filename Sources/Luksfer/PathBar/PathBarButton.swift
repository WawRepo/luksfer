import AppKit

/// A flat button for the path bar: a title (a crumb) or a small symbol (a › chevron), with a soft
/// background on hover and while pressed. A button with `pressHandler` acts on mouse-down, so a
/// menu opens the moment the button is pressed, like a pop-up button.
final class PathBarButton: NSButton {
    static let horizontalPadding: CGFloat = 5

    /// Draws the title in semibold (the last crumb).
    var isEmphasized = false { didSet { needsDisplay = true } }
    /// Runs on mouse-down (and on an accessibility press) instead of the action.
    var pressHandler: ((PathBarButton) -> Void)?
    /// Keeps the pressed look while this button's menu is open.
    var isOpen = false { didSet { needsDisplay = true } }

    private var isHovered = false { didSet { needsDisplay = true } }

    /// A crumb button showing `title`.
    convenience init(title: String) {
        self.init(frame: .zero)
        self.title = title
        setup()
    }

    /// An icon-only button showing the SF Symbol `symbol`, described by `label` for VoiceOver.
    convenience init(symbol: String, pointSize: CGFloat, label: String) {
        self.init(frame: .zero)
        title = ""
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(config)
        imagePosition = .imageOnly
        contentTintColor = .secondaryLabelColor
        setAccessibilityLabel(label)
        setup()
    }

    private func setup() {
        isBordered = false
        setButtonType(.momentaryPushIn)
        (cell as? NSButtonCell)?.highlightsBy = []  // this class draws its own pressed look
        focusRingType = .none
        target = self
        action = #selector(performPress)
    }

    /// The font crumbs use.
    var titleFont: NSFont {
        isEmphasized ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13)
    }

    /// The width that shows the whole title (or the image) with padding.
    var naturalWidth: CGFloat {
        if let image, title.isEmpty { return ceil(image.size.width) + 6 }
        let width = (title as NSString).size(withAttributes: [.font: titleFont]).width
        return ceil(width) + 2 * Self.horizontalPadding
    }

    // MARK: - Pressing

    /// Set by the owner for title buttons; image buttons use `pressHandler`.
    var onClick: (() -> Void)?

    @objc private func performPress() {
        if let pressHandler { pressHandler(self) } else { onClick?() }
    }

    override func mouseDown(with event: NSEvent) {
        guard let pressHandler else { return super.mouseDown(with: event) }
        isOpen = true
        displayIfNeeded()
        pressHandler(self)
        isOpen = false
        updateHoverFromMouse()
    }

    /// Opens `menu` just below this button.
    func popUp(_ menu: NSMenu) {
        let y = isFlipped ? bounds.maxY + 4 : bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: self)
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidHide() {
        super.viewDidHide()
        isHovered = false
    }

    private func updateHoverFromMouse() {
        guard let window else { isHovered = false; return }
        isHovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted || isOpen {
            NSColor.tertiarySystemFill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        } else if isHovered {
            NSColor.quaternarySystemFill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        if image != nil && title.isEmpty {
            super.draw(dirtyRect)
            return
        }
        drawTitle()
    }

    private func drawTitle() {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: title, attributes: [
            .font: titleFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: style,
        ])
        let height = ceil(text.size().height)
        let rect = NSRect(x: Self.horizontalPadding, y: floor((bounds.height - height) / 2),
                          width: max(0, bounds.width - 2 * Self.horizontalPadding), height: height)
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
