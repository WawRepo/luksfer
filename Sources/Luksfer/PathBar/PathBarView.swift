import AppKit
import LuksferCore

/// What the user picked in a path bar. The host does the navigating.
protocol PathBarViewDelegate: AnyObject {
    /// Open `folder`; when `file` is set, select it there.
    func pathBar(_ bar: PathBarView, navigateTo folder: URL, select file: URL?)
    /// "term", "terminal" or "cmd" was typed: open the terminal in the bar's folder.
    func pathBarOpenTerminal(_ bar: PathBarView)
    /// Typing ended (Enter, Esc or a click elsewhere); the host gives focus back to the list.
    func pathBarDidEndEditing(_ bar: PathBarView)
}

/// A pane's path bar. It shows the folder as clickable breadcrumbs; a click on its empty end or
/// ⌘L (`beginEditing()`) turns it into a text field for typing or pasting a path, with folder
/// suggestions, Tab completion and a clear message for a wrong path.
final class PathBarView: NSView {
    static let height: CGFloat = 28

    /// The 16 pt generic folder icon. Never the item's own icon: that can read a cloud file.
    static let folderIcon: NSImage = {
        let image = (NSWorkspace.shared.icon(for: .folder).copy() as? NSImage) ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        return image
    }()

    weak var delegate: PathBarViewDelegate?

    /// The folder shown. Setting it redraws the crumbs and calls no delegate method.
    var folder: URL { didSet { reloadCrumbs() } }
    /// The bar's pane is the active one. Drawn the same for now: the pane shows the active mark.
    var isActive = true
    private(set) var isEditing = false
    /// Hidden folders appear in the › menus (follows the pane's "show hidden files").
    var showsHiddenFolders = false

    /// The home folder, its crumb title and the startup disk name, for the first crumb.
    var home = FileManager.default.homeDirectoryForCurrentUser { didSet { reloadCrumbs() } }
    var userName = FileManager.default.homeDirectoryForCurrentUser.lastPathComponent { didSet { reloadCrumbs() } }
    var rootName = PathBarView.startupDiskName { didSet { reloadCrumbs() } }

    let iconView = NSImageView(image: PathBarView.folderIcon)
    let crumbsView = PathCrumbsView()
    let field = NSTextField(string: "")
    let popup = PathPopup()

    // Editing state (see PathBarView+Editing.swift).
    var hasError = false { didSet { needsDisplay = true } }
    var suggestions: [URL] = []
    var suggestionTitles: [String] = []
    var highlighted: Int?
    var suggestionGeneration = 0
    var clickMonitor: Any?
    let suggestionQueue = DispatchQueue(label: "luksfer.pathbar.suggestions", qos: .userInitiated)

    init(folder: URL) {
        self.folder = folder
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: Self.height))
        setUp()
        reloadCrumbs()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }

    private func setUp() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Path")

        iconView.imageScaling = .scaleProportionallyDown
        iconView.setAccessibilityElement(false)
        addSubview(iconView)

        crumbsView.onOpen = { [weak self] crumb in self?.open(crumb.url) }
        crumbsView.onChevron = { [weak self] crumb, button in self?.showFolderMenu(for: crumb, from: button) }
        crumbsView.onOverflow = { [weak self] crumbs, button in self?.showCrumbMenu(crumbs, from: button) }
        crumbsView.onEdit = { [weak self] in self?.beginEditing() }
        addSubview(crumbsView)

        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setAccessibilityLabel("Path")
        field.delegate = self
        field.isHidden = true
        addSubview(field)

        popup.onPick = { [weak self] index in self?.goToSuggestion(at: index) }
        popup.onHover = { [weak self] index in self?.setHighlight(index) }
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    // MARK: - Public actions

    /// ⌘L: switch to the text field with the whole absolute path selected.
    func beginEditing() {
        beginEditing(text: folder.path, selectAll: true)
    }

    /// Ends typing without going anywhere. No delegate call: the caller decides the focus.
    func cancelEditing() {
        finishEditing()
    }

    /// Puts the folder's absolute path on the clipboard as text.
    func copyPathToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(folder.path, forType: .string)
    }

    // MARK: - Switching modes

    /// Switches to the text field with `text`; all selected, or the cursor at the end.
    func beginEditing(text: String, selectAll: Bool) {
        guard let window else { return }
        if !isEditing {
            isEditing = true
            crumbsView.isHidden = true
            field.isHidden = false
            installClickMonitor()
        }
        hasError = false
        popup.close()
        field.stringValue = text
        window.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            if selectAll {
                editor.selectAll(nil)
            } else {
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
                refreshSuggestions()
            }
        }
        needsDisplay = true
    }

    /// Back to breadcrumbs; closes the list. Calls no delegate method.
    func finishEditing() {
        guard isEditing else { return }
        isEditing = false
        hasError = false
        suggestions = []
        suggestionTitles = []
        highlighted = nil
        suggestionGeneration += 1
        popup.close()
        removeClickMonitor()
        if let window, let editor = field.currentEditor(), window.firstResponder === editor {
            window.makeFirstResponder(nil)
        }
        field.isHidden = true
        crumbsView.isHidden = false
        needsDisplay = true
    }

    // MARK: - Crumbs

    private func reloadCrumbs() {
        crumbsView.setCrumbs(PathCrumbs.crumbs(for: folder, home: home, userName: userName, rootName: rootName))
    }

    func open(_ url: URL) {
        delegate?.pathBar(self, navigateTo: url, select: nil)
    }

    /// The startup disk's name as Finder shows it, e.g. "Macintosh HD".
    static let startupDiskName: String = {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey])
        return values?.volumeLocalizedName ?? "Macintosh HD"
    }()

    // MARK: - Layout and drawing

    override func layout() {
        super.layout()
        let iconX: CGFloat = 7
        iconView.frame = NSRect(x: iconX, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let contentX = iconX + 16 + 3
        crumbsView.frame = NSRect(x: contentX, y: 0, width: max(0, bounds.width - contentX - 2),
                                  height: bounds.height)
        let fieldHeight = field.intrinsicContentSize.height
        field.frame = NSRect(x: contentX + 3, y: floor((bounds.height - fieldHeight) / 2),
                             width: max(0, bounds.width - contentX - 9), height: fieldHeight)
        popup.reposition(below: self)
    }

    override func mouseDown(with event: NSEvent) {
        if !isEditing { beginEditing() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.textBackgroundColor.setFill()
        shape.fill()
        shape.lineWidth = 1
        borderColor.setStroke()
        shape.stroke()
        if hasError || isEditing {
            // A second, inner line makes the editing and error states easy to see.
            let inner = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 5, yRadius: 5)
            borderColor.withAlphaComponent(0.35).setStroke()
            inner.stroke()
        }
    }

    private var borderColor: NSColor {
        if hasError { return .systemRed }
        if isEditing { return .controlAccentColor }
        return .separatorColor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { finishEditing() }
    }
}
