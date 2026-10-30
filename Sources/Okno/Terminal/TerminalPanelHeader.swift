import AppKit

/// The 28 pt strip above the terminal: "Terminal" and the folder name on the left; the Follow
/// checkbox, "Open in Terminal app" and close on the right.
final class TerminalPanelHeader: NSView {
    static let height: CGFloat = 28

    var onFollowChanged: ((Bool) -> Void)?
    var onOpenInTerminalApp: (() -> Void)?
    var onClose: (() -> Void)?

    var follow: Bool {
        get { followCheckbox.state == .on }
        set { followCheckbox.state = newValue ? .on : .off }
    }

    private let titleLabel = NSTextField(labelWithString: "Terminal")
    private let folderLabel = NSTextField(labelWithString: "")
    private let followCheckbox = NSButton(checkboxWithTitle: "Follow", target: nil, action: nil)
    private let openButton = NSButton(title: "Open in Terminal app", target: nil, action: nil)
    private let closeButton = NSButton(title: "", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows the folder's name, and its full path as a tooltip. Nil clears it.
    func setFolder(_ folder: URL?) {
        guard let folder else {
            folderLabel.stringValue = ""
            folderLabel.toolTip = nil
            return
        }
        let path = folder.path
        folderLabel.stringValue = path == "/" ? "/" : folder.lastPathComponent
        folderLabel.toolTip = (path as NSString).abbreviatingWithTildeInPath
    }

    override func draw(_ dirtyRect: NSRect) {
        // Fill the bounds only: views do not clip by default, and dirtyRect can reach outside.
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.intersection(bounds).fill()
        // A hairline separator along the top edge.
        let line = 1 / (window?.backingScaleFactor ?? 2)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - line, width: bounds.width, height: line).fill()
    }

    private func build() {
        let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        folderLabel.font = small
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        folderLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        followCheckbox.controlSize = .small
        followCheckbox.font = small
        followCheckbox.state = .on
        followCheckbox.target = self
        followCheckbox.action = #selector(followClicked)
        followCheckbox.toolTip = "Follow the active pane: cd in the terminal moves the pane, "
            + "and opening a folder in the pane moves the terminal while it waits at its prompt."

        openButton.controlSize = .small
        openButton.font = small
        openButton.bezelStyle = .push
        openButton.image = NSImage(systemSymbolName: "arrow.up.forward.app",
                                   accessibilityDescription: nil)
        openButton.imagePosition = .imageLeading
        openButton.imageScaling = .scaleProportionallyDown
        openButton.target = self
        openButton.action = #selector(openClicked)
        openButton.toolTip = "Open this folder in the terminal app chosen in Settings"

        let symbol = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close terminal")?
            .withSymbolConfiguration(symbol)
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = "Close the terminal"
        closeButton.setAccessibilityLabel("Close terminal")

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 8)
        stack.addView(titleLabel, in: .leading)
        stack.addView(folderLabel, in: .leading)
        stack.addView(followCheckbox, in: .trailing)
        stack.addView(openButton, in: .trailing)
        stack.addView(closeButton, in: .trailing)
        stack.setCustomSpacing(12, after: followCheckbox)
        stack.setCustomSpacing(6, after: openButton)
        // Never push the host's layout wider: in a narrow panel the button goes first, then
        // the views clip.
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        stack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        stack.setVisibilityPriority(NSStackView.VisibilityPriority(rawValue: 500), for: openButton)

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @objc private func followClicked() { onFollowChanged?(follow) }
    @objc private func openClicked() { onOpenInTerminalApp?() }
    @objc private func closeClicked() { onClose?() }
}
