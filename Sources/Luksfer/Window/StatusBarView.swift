import AppKit

/// The bar at the bottom of the window: item counts on the left; a short message after an action,
/// file operation progress and free space on the right.
final class StatusBarView: NSView {
    let infoLabel = NSTextField(labelWithString: "")
    let freeLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let progressStack: NSStackView
    private let messageIcon = NSImageView(image: .symbol("checkmark.circle.fill", nil))
    private let messageLabel = NSTextField(labelWithString: "")
    private let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    private let messageStack: NSStackView
    private var messageUndo: (() -> Void)?
    private var messageTimeout: DispatchWorkItem?
    var onStop: (() -> Void)?

    /// The message shown now, or "" (the self-test reads it).
    var message: String { messageStack.isHidden ? "" : messageLabel.stringValue }

    override init(frame: NSRect) {
        progressStack = NSStackView(views: [progressLabel, progressBar, stopButton])
        messageStack = NSStackView(views: [messageIcon, messageLabel, undoButton])
        super.init(frame: frame)
        for l in [infoLabel, freeLabel, progressLabel, messageLabel] {
            l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            l.textColor = .secondaryLabelColor
            l.lineBreakMode = .byTruncatingMiddle
        }
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.controlSize = .small
        progressBar.widthAnchor.constraint(equalToConstant: 140).isActive = true
        stopButton.controlSize = .small
        stopButton.bezelStyle = .push
        stopButton.target = self
        stopButton.action = #selector(stop)
        progressStack.spacing = 8
        progressStack.isHidden = true
        messageLabel.textColor = .labelColor
        messageIcon.contentTintColor = .systemGreen
        messageIcon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        undoButton.controlSize = .small
        undoButton.bezelStyle = .push
        undoButton.target = self
        undoButton.action = #selector(undoMessage)
        messageStack.spacing = 6
        messageStack.isHidden = true
        let separator = NSBox()
        separator.boxType = .separator
        let row = NSStackView(views: [infoLabel, NSView(), messageStack, progressStack, freeLabel])
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        progressLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Any later step on the undo stack (or an undo) ends the message, so its Undo button
        // always undoes the action it names.
        let undo = AppServices.shared.undoManager
        for name in [Notification.Name.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(undoStackChanged), name: name, object: undo)
        }
        for v in [separator, row] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: separator.bottomAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Shows a running operation; `fraction` nil means "unknown yet".
    func showProgress(_ text: String, fraction: Double?) {
        hideMessage()
        progressStack.isHidden = false
        progressLabel.stringValue = text
        progressBar.isIndeterminate = fraction == nil
        if let fraction { progressBar.doubleValue = fraction } else { progressBar.startAnimation(nil) }
    }

    func hideProgress() {
        progressStack.isHidden = true
        progressBar.stopAnimation(nil)
    }

    @objc private func stop() { onStop?() }

    // MARK: Messages

    /// Shows what an action did ("Moved 2 items to the Trash") for 6 seconds. `undo` adds an Undo
    /// button. VoiceOver reads the message out.
    func showMessage(_ text: String, undo: (() -> Void)? = nil) {
        messageLabel.stringValue = text
        messageUndo = undo
        undoButton.isHidden = undo == nil
        messageStack.isHidden = false
        messageTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self?.hideMessage() }
        messageTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: timeout)
        if let window {
            NSAccessibility.post(element: window, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    func hideMessage() {
        messageTimeout?.cancel()
        messageTimeout = nil
        messageUndo = nil
        messageStack.isHidden = true
    }

    @objc private func undoMessage() {
        let undo = messageUndo
        hideMessage()
        undo?()
    }

    @objc private func undoStackChanged(_ note: Notification) {
        if messageUndo != nil { hideMessage() }
    }
}
