import AppKit
import OknoCore

/// The breadcrumb row of the path bar: `crumb › crumb › crumb ›` and an empty end that starts
/// typing. When the crumbs do not fit, the leading ones collapse into a "…" button.
final class PathCrumbsView: NSView {
    static let maxCrumbWidth: CGFloat = 160
    static let minLastCrumbWidth: CGFloat = 40
    static let chevronWidth: CGFloat = 16
    static let minEndWidth: CGFloat = 24
    static let buttonHeight: CGFloat = 22

    /// A crumb was clicked.
    var onOpen: ((PathCrumb) -> Void)?
    /// The › after crumb `index` was pressed; show its subfolders from `button`.
    var onChevron: ((PathCrumb, PathBarButton) -> Void)?
    /// The "…" button was pressed; show the hidden `crumbs` from `button`.
    var onOverflow: (([PathCrumb], PathBarButton) -> Void)?
    /// The empty end was clicked.
    var onEdit: (() -> Void)?

    private(set) var crumbs: [PathCrumb] = []
    private var crumbButtons: [PathBarButton] = []
    private var chevronButtons: [PathBarButton] = []
    private let overflowButton = PathBarButton(title: "…")
    private let endButton = PathBarEndButton()
    /// How many leading crumbs are collapsed into "…".
    private(set) var collapsedCount = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        clipsToBounds = true
        overflowButton.setAccessibilityLabel("Show earlier folders in the path")
        overflowButton.pressHandler = { [weak self] button in
            guard let self else { return }
            self.onOverflow?(Array(self.crumbs.prefix(self.collapsedCount)), button)
        }
        endButton.target = self
        endButton.action = #selector(endClicked)
        addSubview(overflowButton)
        addSubview(endButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func setCrumbs(_ newCrumbs: [PathCrumb]) {
        guard newCrumbs != crumbs else { return }
        crumbs = newCrumbs
        (crumbButtons + chevronButtons).forEach { $0.removeFromSuperview() }
        crumbButtons = crumbs.enumerated().map { index, crumb in
            let button = PathBarButton(title: crumb.title)
            button.isEmphasized = index == newCrumbs.count - 1
            button.toolTip = crumb.url.path
            button.onClick = { [weak self] in self?.onOpen?(crumb) }
            return button
        }
        chevronButtons = crumbs.map { crumb in
            let button = PathBarButton(symbol: "chevron.right", pointSize: 9,
                                       label: "Show folders in \(crumb.title)")
            button.pressHandler = { [weak self] button in self?.onChevron?(crumb, button) }
            return button
        }
        (crumbButtons + chevronButtons).forEach { addSubview($0) }
        needsLayout = true
    }

    @objc private func endClicked() { onEdit?() }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let count = crumbs.count
        let chevron = Self.chevronWidth
        var widths = crumbButtons.map { min(Self.maxCrumbWidth, $0.naturalWidth) }
        let available = bounds.width - Self.minEndWidth

        // Keep as many trailing crumbs as fit; the rest go behind "…".
        var first = 0
        let total = widths.reduce(0, +) + chevron * CGFloat(count)
        if count > 1 && total > available {
            var used = overflowButton.naturalWidth + chevron + widths[count - 1] + chevron
            first = count - 1
            while first > 1 && used + widths[first - 1] + chevron <= available {
                first -= 1
                used += widths[first] + chevron
            }
        }
        collapsedCount = first

        if count > 0 {
            let others = (first..<count - 1).reduce(CGFloat(0)) { $0 + widths[$1] + chevron }
            let overflow = first > 0 ? overflowButton.naturalWidth + chevron : 0
            let room = available - overflow - others - chevron
            widths[count - 1] = max(Self.minLastCrumbWidth, min(widths[count - 1], room))
        }

        var x: CGFloat = 0
        let y = floor((bounds.height - Self.buttonHeight) / 2)
        func place(_ view: NSView, _ width: CGFloat) {
            view.frame = NSRect(x: x, y: y, width: width, height: Self.buttonHeight)
            view.isHidden = false
            x += width
        }
        overflowButton.isHidden = true
        crumbButtons.forEach { $0.isHidden = true }
        chevronButtons.forEach { $0.isHidden = true }
        if first > 0 {
            place(overflowButton, overflowButton.naturalWidth)
            place(chevronButtons[first - 1], chevron)
        }
        for index in first..<count {
            place(crumbButtons[index], widths[index])
            place(chevronButtons[index], chevron)
        }
        endButton.frame = NSRect(x: x, y: 0, width: max(0, bounds.width - x), height: bounds.height)
    }
}

/// The empty end of the path bar: an I-beam cursor, and a click starts typing a path.
final class PathBarEndButton: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        isTransparent = true
        focusRingType = .none
        setAccessibilityLabel("Type a path")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }
}
