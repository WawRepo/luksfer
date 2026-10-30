import AppKit

/// The bar at the bottom of the window: item counts on the left, file operation progress and free
/// space on the right.
final class StatusBarView: NSView {
    let infoLabel = NSTextField(labelWithString: "")
    let freeLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let progressStack: NSStackView
    var onStop: (() -> Void)?

    override init(frame: NSRect) {
        progressStack = NSStackView(views: [progressLabel, progressBar, stopButton])
        super.init(frame: frame)
        for l in [infoLabel, freeLabel, progressLabel] {
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
        let separator = NSBox()
        separator.boxType = .separator
        let row = NSStackView(views: [infoLabel, NSView(), progressStack, freeLabel])
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        progressLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
}
