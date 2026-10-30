import AppKit
import LuksferCore

protocol PaneDelegate: AnyObject {
    func paneDidBecomeActive(_ pane: PaneViewController)
    func paneDidChangeFolder(_ pane: PaneViewController)
    func paneSelectionDidChange(_ pane: PaneViewController)
    func paneSortDidChange(_ pane: PaneViewController)
    func paneOpenTerminal(_ pane: PaneViewController)
    func pane(_ pane: PaneViewController, handle key: ListKey) -> Bool
    func pane(_ pane: PaneViewController, menuFor items: [FileItem]) -> NSMenu?
    func pane(_ pane: PaneViewController, rename item: FileItem, to name: String)
    func pane(_ pane: PaneViewController, drop urls: [URL], into folder: URL, operation: DropOperation) -> Bool
    func pane(_ pane: PaneViewController, didCopyPaths count: Int)
}

/// One pane: back, forward and up, the path bar, Copy path, the search box, and the file list.
/// Each pane has its own folder, history, selection, sort and search (PRD §6.1).
final class PaneViewController: NSViewController {
    weak var delegate: PaneDelegate?
    let list = FileListViewController()
    let pathBar: PathBarView
    private(set) var history: NavigationHistory
    private var watcher: FolderWatcher?

    private let backButton = PaneViewController.iconButton("arrow.left", "Back")
    private let forwardButton = PaneViewController.iconButton("arrow.right", "Forward")
    private let upButton = PaneViewController.iconButton("arrow.up", "Up one folder")
    private let copyPathButton = PaneViewController.iconButton("link", "Copy path")
    let searchField = NSSearchField()
    private let activeMark = NSBox()
    private let header = NSView()
    private let spinner = NSProgressIndicator()
    private let messageBox = NSStackView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let messageButton = NSButton(title: "Open Privacy Settings", target: nil, action: nil)
    private var spinnerWork: DispatchWorkItem?

    var folder: URL { history.current }

    var isActive = false {
        didSet {
            activeMark.fillColor = isActive ? .controlAccentColor : .clear
            pathBar.isActive = isActive
        }
    }

    /// The accent line on top of the active pane only shows when two panes are open.
    var showsActiveMark = false {
        didSet { activeMark.isHidden = !showsActiveMark }
    }

    init(folder: URL, sort: FileSortOrder) {
        history = NavigationHistory(start: folder)
        pathBar = PathBarView(folder: folder)
        super.init(nibName: nil, bundle: nil)
        list.sortOrder = sort
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        view = root

        activeMark.boxType = .custom
        activeMark.borderWidth = 0
        activeMark.fillColor = .clear
        activeMark.isHidden = true
        activeMark.translatesAutoresizingMaskIntoConstraints = false

        backButton.action = #selector(goBack)
        forwardButton.action = #selector(goForward)
        upButton.action = #selector(goUp)
        copyPathButton.action = #selector(copyPath)
        copyPathButton.toolTip = "Copy path (⌥⌘C)"
        for b in [backButton, forwardButton, upButton, copyPathButton] { b.target = self }

        pathBar.delegate = self
        pathBar.translatesAutoresizingMaskIntoConstraints = false
        pathBar.setContentHuggingPriority(.defaultLow, for: .horizontal)

        searchField.placeholderString = "Search"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.controlSize = .regular
        searchField.setAccessibilityLabel("Search this folder")

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [backButton, forwardButton, upButton, pathBar, copyPathButton, spinner, searchField])
        row.orientation = .horizontal
        row.spacing = 4
        row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        row.setCustomSpacing(8, after: upButton)
        row.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(row)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addChild(list)
        list.delegate = self
        let listView = list.view
        listView.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.preferredMaxLayoutWidth = 360
        messageButton.target = self
        messageButton.action = #selector(openPrivacySettings)
        messageButton.bezelStyle = .push
        messageBox.orientation = .vertical
        messageBox.spacing = 10
        messageBox.addArrangedSubview(messageLabel)
        messageBox.addArrangedSubview(messageButton)
        messageBox.isHidden = true
        messageBox.translatesAutoresizingMaskIntoConstraints = false

        for v in [header, separator, listView, messageBox, activeMark] as [NSView] { root.addSubview(v) }
        NSLayoutConstraint.activate([
            activeMark.topAnchor.constraint(equalTo: root.topAnchor),
            activeMark.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            activeMark.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            activeMark.heightAnchor.constraint(equalToConstant: 2),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 40),
            row.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: 1),
            pathBar.heightAnchor.constraint(equalToConstant: 28),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            listView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            listView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            messageBox.centerXAnchor.constraint(equalTo: listView.centerXAnchor),
            messageBox.centerYAnchor.constraint(equalTo: listView.centerYAnchor),
            messageBox.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
        ])
        let searchWidth = searchField.widthAnchor.constraint(equalToConstant: 170)
        searchWidth.priority = .defaultLow
        searchWidth.isActive = true
        // In a narrow pane the search box shrinks first; the path bar keeps room for a few crumbs.
        let pathWidth = pathBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        pathWidth.priority = .defaultHigh
        pathWidth.isActive = true
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        show(folder, select: nil)
    }

    private static func iconButton(_ symbol: String, _ label: String) -> NSButton {
        let b = NSButton(image: .symbol(symbol, label, size: 14, weight: .medium), target: nil, action: nil)
        b.bezelStyle = .accessoryBarAction
        b.isBordered = false
        b.setAccessibilityLabel(label)
        b.toolTip = label
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 26).isActive = true
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return b
    }

    // MARK: Navigation

    /// Opens a folder (or a file's folder with the file selected) and records it in the history.
    func navigate(to url: URL, select: [URL]? = nil) {
        var isDir: ObjCBool = false
        let target = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), !isDir.boolValue {
            navigate(to: target.deletingLastPathComponent(), select: [target])
            return
        }
        history.visit(target)
        show(target, select: select)
    }

    @objc func goBack() { let from = folder; if let url = history.goBack() { show(url, select: cameFrom(from, into: url)) } }
    @objc func goForward() { let from = folder; if let url = history.goForward() { show(url, select: cameFrom(from, into: url)) } }

    /// Going back to a parent selects the folder you came from (like Explorer).
    private func cameFrom(_ from: URL, into url: URL) -> [URL]? {
        from.deletingLastPathComponent().standardizedFileURL == url.standardizedFileURL ? [from] : nil
    }

    @objc func goUp() {
        guard !folder.isRootFolder else { return }
        let child = folder
        navigate(to: folder.deletingLastPathComponent(), select: [child])
    }

    func reload() {
        pathBar.showsHiddenFolders = AppServices.shared.settings.showHidden
        list.reload()
    }

    private func show(_ url: URL, select: [URL]?) {
        guard isViewLoaded else { return }
        pathBar.folder = url
        pathBar.showsHiddenFolders = AppServices.shared.settings.showHidden
        updateButtons()
        if !searchField.stringValue.isEmpty {
            searchField.stringValue = ""
            list.filterQuery = ""
        }
        messageBox.isHidden = true
        spinnerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.spinner.startAnimation(nil) }
        spinnerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        list.load(url, select: select) { [weak self] error in
            guard let self else { return }
            self.spinnerWork?.cancel()
            self.spinner.stopAnimation(nil)
            self.showError(error)
            self.updateMessage()
        }
        watcher = FolderWatcher(folder: url, onChange: { [weak self] in self?.list.reload() },
                                onGone: { [weak self] in self?.folderWentAway() })
        delegate?.paneDidChangeFolder(self)
    }

    private func folderWentAway() {
        var up = folder
        while !up.isRootFolder && !FileManager.default.fileExists(atPath: up.path) { up = up.deletingLastPathComponent() }
        if up != folder { navigate(to: up) } else { list.reload() }
    }

    private func updateButtons() {
        backButton.isEnabled = history.canGoBack
        forwardButton.isEnabled = history.canGoForward
        upButton.isEnabled = !folder.isRootFolder
    }

    /// The empty-folder and no-match messages; errors win.
    private func updateMessage() {
        guard isViewLoaded, list.loadError == nil else { return }
        guard list.items.isEmpty else { messageBox.isHidden = true; return }
        let query = searchField.stringValue
        messageLabel.stringValue = query.isEmpty
            ? "This folder is empty.\nRight-click to add a folder or a file."
            : "Nothing here matches “\(query)”."
        messageButton.isHidden = true
        messageBox.isHidden = false
    }

    private func showError(_ error: Error?) {
        guard let error else { messageBox.isHidden = true; return }
        let code = (error as? POSIXError)?.code
        if code == .EPERM {
            messageLabel.stringValue = "macOS blocked Luksfer from reading this folder.\nAllow it in System Settings › Privacy & Security › Files and Folders, or give Luksfer Full Disk Access."
            messageButton.isHidden = false
        } else if code == .EACCES {
            messageLabel.stringValue = "You don't have permission to see what is in this folder."
            messageButton.isHidden = true
        } else if code == .ENOENT {
            // The folder went away while we came here: go to the nearest folder that exists.
            if !FileManager.default.fileExists(atPath: folder.path) { folderWentAway(); return }
            messageLabel.stringValue = "This folder does not exist any more."
            messageButton.isHidden = true
        } else {
            messageLabel.stringValue = "Luksfer could not read this folder.\n\(error.localizedDescription)"
            messageButton.isHidden = true
        }
        messageBox.isHidden = false
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Actions

    @objc func copyPath() {
        let urls = list.selectedURLs.isEmpty ? [folder] : list.selectedURLs
        let pasteboard = FileClipboard.pasteboard   // a private one in self-test runs
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        delegate?.pane(self, didCopyPaths: urls.count)
    }

    func focusSearch() { view.window?.makeFirstResponder(searchField) }

    @objc private func searchChanged() { list.filterQuery = searchField.stringValue }
}

extension PaneViewController: PathBarViewDelegate {
    func pathBar(_ bar: PathBarView, navigateTo folder: URL, select file: URL?) {
        navigate(to: folder, select: file.map { [$0] })
        list.focus()
    }

    func pathBarOpenTerminal(_ bar: PathBarView) {
        delegate?.paneOpenTerminal(self)
    }

    func pathBarDidEndEditing(_ bar: PathBarView) {
        list.focus()
    }
}

extension PaneViewController: FileListDelegate {
    func fileListDidActivate(_ list: FileListViewController) { delegate?.paneDidBecomeActive(self) }

    func fileList(_ list: FileListViewController, open items: [FileItem]) {
        if items.count == 1, items[0].isFolder {
            navigate(to: items[0].url)
            return
        }
        for item in items {
            if item.isFolder { navigate(to: item.url) } else { NSWorkspace.shared.open(item.url) }
        }
    }

    func fileList(_ list: FileListViewController, handle key: ListKey) -> Bool {
        switch key {
        case .back: goBack(); return true
        case .up: goUp(); return true
        default: return delegate?.pane(self, handle: key) ?? false
        }
    }

    func fileListSelectionDidChange(_ list: FileListViewController) { delegate?.paneSelectionDidChange(self) }
    func fileListItemsDidChange(_ list: FileListViewController) { updateMessage() }
    func fileListSortDidChange(_ list: FileListViewController) { delegate?.paneSortDidChange(self) }

    func fileList(_ list: FileListViewController, menuFor items: [FileItem]) -> NSMenu? {
        delegate?.paneDidBecomeActive(self)
        return delegate?.pane(self, menuFor: items)
    }

    func fileList(_ list: FileListViewController, rename item: FileItem, to name: String) {
        delegate?.pane(self, rename: item, to: name)
    }

    func fileList(_ list: FileListViewController, drop urls: [URL], into folder: URL, operation: DropOperation) -> Bool {
        delegate?.pane(self, drop: urls, into: folder, operation: operation) ?? false
    }
}

extension PaneViewController: NSSearchFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.moveDown(_:)) {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                searchField.stringValue = ""
                list.filterQuery = ""
            }
            list.focus()
            if list.tableView.selectedRow < 0, !list.items.isEmpty { list.tableView.selectRowIndexes([0], byExtendingSelection: false) }
            return true
        }
        return false
    }
}
