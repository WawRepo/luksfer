import AppKit
import OknoCore

protocol SidebarDelegate: AnyObject {
    func sidebar(_ sidebar: SidebarViewController, open url: URL)
    func sidebar(_ sidebar: SidebarViewController, openInOtherPane url: URL)
    func sidebar(_ sidebar: SidebarViewController, drop urls: [URL], into folder: URL, operation: DropOperation) -> Bool
}

/// One row of the sidebar. Group rows have a `section`; the others have a `url`.
final class SidebarNode: NSObject {
    enum Section: String { case favorites = "Favorites", thisMac = "This Mac", locations = "Locations" }

    let section: Section?
    let title: String
    let url: URL?
    let symbol: String
    let favoriteIndex: Int?
    let ejectable: Bool
    var children: [SidebarNode] = []

    init(section: Section) {
        self.section = section
        title = section.rawValue
        url = nil
        symbol = ""
        favoriteIndex = nil
        ejectable = false
    }

    init(title: String, url: URL, symbol: String, favoriteIndex: Int? = nil, ejectable: Bool = false) {
        section = nil
        self.title = title
        self.url = url
        self.symbol = symbol
        self.favoriteIndex = favoriteIndex
        self.ejectable = ejectable
    }
}

/// The sidebar: Favorites (pin, reorder, rename, unpin), This Mac, and Locations (PRD §6.4).
final class SidebarViewController: NSViewController {
    weak var delegate: SidebarDelegate?
    private let outline = NSOutlineView()
    private var groups: [SidebarNode] = []
    private var editingFavorites = false
    private var selectingProgrammatically = false
    private var currentFolder: URL?
    private static let favoriteType = NSPasteboard.PasteboardType("app.okno.favorite")

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        view = scroll

        let column = NSTableColumn(identifier: .init("main"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.floatsGroupRows = false
        outline.indentationPerLevel = 0
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked)
        outline.setAccessibilityLabel("Sidebar")
        outline.registerForDraggedTypes([.fileURL, Self.favoriteType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        scroll.documentView = outline

        rebuild()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(settingsChanged), name: .oknoSettingsChanged, object: nil)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didMountNotification, object: nil)
        ws.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didUnmountNotification, object: nil)
        ws.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didRenameVolumeNotification, object: nil)
    }

    // MARK: Model

    private func rebuild() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let favorites = SidebarNode(section: .favorites)
        favorites.children = AppServices.shared.settings.favorites.enumerated().map { i, f in
            SidebarNode(title: f.label, url: f.url, symbol: "folder", favoriteIndex: i)
        }

        let mac = SidebarNode(section: .thisMac)
        mac.children = [
            SidebarNode(title: home.lastPathComponent, url: home, symbol: "house"),
            SidebarNode(title: "Desktop", url: home.appendingPathComponent("Desktop", isDirectory: true), symbol: "menubar.dock.rectangle"),
            SidebarNode(title: "Documents", url: home.appendingPathComponent("Documents", isDirectory: true), symbol: "doc"),
            SidebarNode(title: "Downloads", url: home.appendingPathComponent("Downloads", isDirectory: true), symbol: "arrow.down.circle"),
            SidebarNode(title: "Pictures", url: home.appendingPathComponent("Pictures", isDirectory: true), symbol: "photo"),
        ] + CloudPlaces.providers().map { SidebarNode(title: $0.0, url: $0.1, symbol: "cloud") }

        let locations = SidebarNode(section: .locations)
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        locations.children = [
            SidebarNode(title: root.displayName, url: root, symbol: "internaldrive"),
            SidebarNode(title: "Applications", url: URL(fileURLWithPath: "/Applications", isDirectory: true), symbol: "square.grid.2x2"),
        ] + externalVolumes() + [
            SidebarNode(title: "Trash", url: home.appendingPathComponent(".Trash", isDirectory: true), symbol: "trash"),
        ]

        groups = [favorites, mac, locations]
        outline.reloadData()
        let collapsed = Set(AppServices.shared.settings.collapsedSidebarSections)
        for g in groups {
            if collapsed.contains(g.title) { outline.collapseItem(g) } else { outline.expandItem(g) }
        }
        if let currentFolder { highlight(currentFolder) }
    }

    private func externalVolumes() -> [SidebarNode] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsRootFileSystemKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsRootFileSystem != true,
                  url.path.hasPrefix("/Volumes/") else { return nil }
            let ejectable = (v.volumeIsEjectable ?? false) || (v.volumeIsRemovable ?? false) || !(v.volumeIsInternal ?? true)
            return SidebarNode(title: v.volumeLocalizedName ?? url.lastPathComponent, url: url,
                               symbol: ejectable ? "externaldrive" : "internaldrive", ejectable: ejectable)
        }
    }

    @objc private func settingsChanged() { rebuild() }
    @objc private func volumesChanged() { rebuild() }

    /// Highlights the row for the folder a pane shows, if there is one.
    func highlight(_ folder: URL) {
        currentFolder = folder
        let path = folder.standardizedFileURL.path
        for g in groups {
            if let node = g.children.first(where: { $0.url?.standardizedFileURL.path == path }) {
                let row = outline.row(forItem: node)
                if row >= 0 {
                    selectingProgrammatically = true
                    outline.selectRowIndexes([row], byExtendingSelection: false)
                    selectingProgrammatically = false
                    return
                }
            }
        }
        outline.deselectAll(nil)
    }

    // MARK: Actions

    @objc private func clicked() {
        guard let node = outline.item(atRow: outline.clickedRow) as? SidebarNode, let url = node.url else { return }
        delegate?.sidebar(self, open: url)
    }

    private func clickedNode() -> SidebarNode? { outline.item(atRow: outline.clickedRow) as? SidebarNode }

    @objc private func openClicked(_ sender: NSMenuItem) {
        if let url = (sender.representedObject as? SidebarNode)?.url { delegate?.sidebar(self, open: url) }
    }

    @objc private func openInOtherPane(_ sender: NSMenuItem) {
        if let url = (sender.representedObject as? SidebarNode)?.url { delegate?.sidebar(self, openInOtherPane: url) }
    }

    @objc private func unpin(_ sender: NSMenuItem) {
        guard let i = (sender.representedObject as? SidebarNode)?.favoriteIndex else { return }
        AppServices.shared.update { $0.favorites.remove(at: i) }
    }

    @objc private func pin(_ sender: NSMenuItem) {
        if let url = (sender.representedObject as? SidebarNode)?.url { AppServices.shared.pin([url]) }
    }

    @objc private func moveFavorite(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? SidebarNode, let i = node.favoriteIndex else { return }
        let to = i + sender.tag
        AppServices.shared.update { s in
            guard to >= 0, to < s.favorites.count else { return }
            s.favorites.swapAt(i, to)
        }
    }

    @objc private func renameFavorite(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? SidebarNode, let i = node.favoriteIndex, let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Rename favorite"
        alert.informativeText = "The label changes. The folder keeps its name and path."
        let field = NSTextField(string: node.title)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            let label = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard response == .alertFirstButtonReturn, !label.isEmpty else { return }
            AppServices.shared.update { s in if i < s.favorites.count { s.favorites[i].label = label } }
        }
    }

    @objc private func toggleEdit(_ sender: Any?) {
        editingFavorites.toggle()
        outline.reloadData()
        for g in groups where !AppServices.shared.settings.collapsedSidebarSections.contains(g.title) { outline.expandItem(g) }
        if let currentFolder { highlight(currentFolder) }
    }

    @objc private func rowButton(_ sender: NSButton) {
        guard let i = sender.cell?.representedObject as? Int else { return }
        AppServices.shared.update { s in
            guard i < s.favorites.count else { return }
            switch sender.tag {
            case -1: if i > 0 { s.favorites.swapAt(i, i - 1) }
            case 1: if i + 1 < s.favorites.count { s.favorites.swapAt(i, i + 1) }
            default: s.favorites.remove(at: i)
            }
        }
    }

    @objc private func eject(_ sender: NSButton) {
        guard let path = sender.cell?.representedObject as? String else { return }
        let url = URL(fileURLWithPath: path)
        DispatchQueue.global().async {
            do { try NSWorkspace.shared.unmountAndEjectDevice(at: url) } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert(error: error)
                    alert.messageText = "Okno could not eject “\(url.lastPathComponent)”."
                    alert.runModal()
                }
            }
        }
    }
}

// MARK: - Outline data

extension SidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SidebarNode)?.children.count ?? groups.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SidebarNode)?.children[index] ?? groups[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarNode)?.section != nil
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarNode)?.section != nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? SidebarNode)?.url != nil
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        if let section = node.section {
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: node.title)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2).isActive = true
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
            if section == .favorites {
                let edit = NSButton(title: editingFavorites ? "Done" : "Edit", target: self, action: #selector(toggleEdit))
                edit.isBordered = false
                edit.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
                edit.contentTintColor = .controlAccentColor
                edit.translatesAutoresizingMaskIntoConstraints = false
                edit.setAccessibilityLabel(editingFavorites ? "Done editing favorites" : "Edit favorites")
                cell.addSubview(edit)
                edit.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -16).isActive = true
                edit.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
            }
            return cell
        }
        let cell = NSTableCellView()
        let image = NSImageView(image: .symbol(node.symbol, nil, size: 14))
        image.contentTintColor = .controlAccentColor
        let label = NSTextField(labelWithString: node.title)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = node.url?.tildePath
        let stack = NSStackView(views: [image, label])
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        image.widthAnchor.constraint(equalToConstant: 18).isActive = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let i = node.favoriteIndex, editingFavorites {
            let count = AppServices.shared.settings.favorites.count
            for (tag, symbol, name) in [(-1, "arrow.up", "Move up"), (1, "arrow.down", "Move down"), (0, "xmark", "Unpin")] {
                let b = NSButton(image: .symbol(symbol, "\(name) \(node.title)", size: 11, weight: .semibold), target: self, action: #selector(rowButton))
                b.isBordered = false
                b.tag = tag
                b.cell?.representedObject = i
                b.toolTip = name
                b.isEnabled = !(tag == -1 && i == 0) && !(tag == 1 && i == count - 1)
                stack.addArrangedSubview(b)
            }
        } else if node.ejectable, let url = node.url {
            let b = NSButton(image: .symbol("eject.fill", "Eject \(node.title)", size: 11), target: self, action: #selector(eject))
            b.isBordered = false
            b.cell?.representedObject = url.path
            b.toolTip = "Eject"
            stack.addArrangedSubview(b)
        }
        cell.addSubview(stack)
        cell.textField = label
        cell.imageView = image
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func outlineViewItemDidCollapse(_ notification: Notification) { saveCollapsed() }
    func outlineViewItemDidExpand(_ notification: Notification) { saveCollapsed() }

    private func saveCollapsed() {
        let collapsed = groups.filter { !outline.isItemExpanded($0) }.map(\.title)
        AppServices.shared.update { $0.collapsedSidebarSections = collapsed }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !selectingProgrammatically, outline.clickedRow < 0,
              let node = outline.item(atRow: outline.selectedRow) as? SidebarNode, let url = node.url else { return }
        // Keyboard selection (arrow keys) opens the folder too.
        delegate?.sidebar(self, open: url)
    }

    // MARK: Drag and drop

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? SidebarNode, let i = node.favoriteIndex else { return nil }
        let pb = NSPasteboardItem()
        pb.setString(String(i), forType: Self.favoriteType)
        return pb
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let node = item as? SidebarNode
        if info.draggingPasteboard.string(forType: Self.favoriteType) != nil {
            return node?.section == .favorites && index >= 0 ? .move : []
        }
        guard let urls = fileURLs(info), !urls.isEmpty else { return [] }
        if node?.section == .favorites {
            // Between favorites (or on the header): pin the dropped folders.
            guard urls.contains(where: isFolder) else { return [] }
            if index < 0 { outlineView.setDropItem(node, dropChildIndex: node?.children.count ?? 0) }
            return .link
        }
        guard let node, let target = node.url, index == NSOutlineViewDropOnItemIndex else { return [] }
        if urls.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == target.standardizedFileURL }) { return [] }
        return operation(for: urls, into: target, info: info) == .copy ? .copy : .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let node = item as? SidebarNode
        if let s = info.draggingPasteboard.string(forType: Self.favoriteType), let from = Int(s) {
            AppServices.shared.update { f in
                guard from < f.favorites.count else { return }
                let moved = f.favorites.remove(at: from)
                f.favorites.insert(moved, at: min(index > from ? index - 1 : index, f.favorites.count))
            }
            return true
        }
        guard let urls = fileURLs(info) else { return false }
        if node?.section == .favorites {
            AppServices.shared.pin(urls.filter(isFolder), at: index >= 0 ? index : nil)
            return true
        }
        guard let target = node?.url else { return false }
        return delegate?.sidebar(self, drop: urls, into: target, operation: operation(for: urls, into: target, info: info)) ?? false
    }

    private func fileURLs(_ info: NSDraggingInfo) -> [URL]? {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    }

    private func isFolder(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    private func operation(for urls: [URL], into target: URL, info: NSDraggingInfo) -> DropOperation {
        let flags = NSEvent.modifierFlags
        let same = urls.first.map { DropRule.sameVolume($0, target) } ?? true
        return DropRule.operation(sameVolume: same, option: flags.contains(.option), command: flags.contains(.command))
    }
}

// MARK: - Context menu

extension SidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let node = clickedNode(), node.url != nil else { return }
        func add(_ title: String, _ action: Selector, tag: Int = 0) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = node
            item.tag = tag
            menu.addItem(item)
        }
        add("Open", #selector(openClicked))
        add("Open in Other Pane", #selector(openInOtherPane))
        menu.addItem(.separator())
        if let i = node.favoriteIndex {
            add("Rename Label…", #selector(renameFavorite))
            if i > 0 { add("Move Up", #selector(moveFavorite), tag: -1) }
            if i + 1 < AppServices.shared.settings.favorites.count { add("Move Down", #selector(moveFavorite), tag: 1) }
            add("Unpin from Favorites", #selector(unpin))
        } else if let url = node.url, !AppServices.shared.isFavorite(url) {
            add("Pin to Favorites", #selector(pin))
        }
    }
}
