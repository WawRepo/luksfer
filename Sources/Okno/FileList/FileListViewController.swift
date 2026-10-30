import AppKit
import OknoCore
import Quartz

protocol FileListDelegate: AnyObject {
    func fileListDidActivate(_ list: FileListViewController)
    func fileList(_ list: FileListViewController, open items: [FileItem])
    func fileList(_ list: FileListViewController, handle key: ListKey) -> Bool
    func fileListSelectionDidChange(_ list: FileListViewController)
    /// The shown items changed (loaded, filtered or reloaded).
    func fileListItemsDidChange(_ list: FileListViewController)
    func fileListSortDidChange(_ list: FileListViewController)
    func fileList(_ list: FileListViewController, menuFor items: [FileItem]) -> NSMenu?
    func fileList(_ list: FileListViewController, rename item: FileItem, to name: String)
    /// Files dropped on the list (`folder` = a folder row or the current folder).
    func fileList(_ list: FileListViewController, drop urls: [URL], into folder: URL, operation: DropOperation) -> Bool
}

/// The details view of one pane: a view-based NSTableView over a sorted, filtered listing.
final class FileListViewController: NSViewController {
    weak var delegate: FileListDelegate?

    private(set) var folder: URL?
    private(set) var allItems: [FileItem] = []
    private(set) var items: [FileItem] = []
    private(set) var loadError: Error?
    var sortOrder = FileSortOrder() {
        didSet { if oldValue != sortOrder { applyItems(keepSelection: true); updateSortIndicator() } }
    }
    var filterQuery = "" {
        didSet { if oldValue != filterQuery { applyItems(keepSelection: true) } }
    }
    /// Items waiting to be moved by a paste (cut): drawn dimmed.
    var dimmedURLs: Set<URL> = [] { didSet { guard isViewLoaded, !items.isEmpty else { return }; tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<items.count), columnIndexes: IndexSet(integer: 0)) } }

    let tableView = FileTableView()
    private let scrollView = NSScrollView()
    private var generation = 0
    private var renaming: (item: FileItem, field: NSTextField, cancelled: Bool)?
    private var onLoaded: [() -> Void] = []

    override func loadView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        view = scrollView

        tableView.style = .fullWidth
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsTypeSelect = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing   // fitNameColumn() sizes Name
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 6, height: 0)
        tableView.gridStyleMask = []
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyDelegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)
        tableView.setAccessibilityLabel("Files")
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)
        tableView.draggingDestinationFeedbackStyle = .regular

        setUpColumns()
        scrollView.documentView = tableView
        NotificationCenter.default.addObserver(self, selector: #selector(columnsChanged), name: NSTableView.columnDidResizeNotification, object: tableView)
        NotificationCenter.default.addObserver(self, selector: #selector(columnsChanged), name: NSTableView.columnDidMoveNotification, object: tableView)
        // The clip view also narrows when a scroll bar appears, without a new layout pass.
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipViewResized), name: NSView.frameDidChangeNotification, object: scrollView.contentView)
    }

    // MARK: Columns

    private func setUpColumns() {
        let saved = AppServices.shared.settings.columns
        let order = saved.isEmpty ? FileColumn.allCases : saved.compactMap { FileColumn(rawValue: $0.id) } + FileColumn.allCases.filter { c in !saved.contains { $0.id == c.rawValue } }
        for column in order {
            let state = saved.first { $0.id == column.rawValue }
            let c = NSTableColumn(identifier: column.identifier)
            c.title = column.title
            c.width = state.map { CGFloat($0.width) } ?? column.defaultWidth
            c.minWidth = column == .name ? 120 : 40
            c.isHidden = column == .name ? false : (state?.hidden ?? column.hiddenByDefault)
            c.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            if column == .size { c.headerCell.alignment = .right }
            tableView.addTableColumn(c)
        }
        let menu = NSMenu()
        menu.delegate = self
        tableView.headerView?.menu = menu
        updateSortIndicator()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        fitNameColumn()
    }

    /// Name takes the width the other columns leave (at least its minimum), so Type and Size stay
    /// in view in a narrow pane. Runs when the pane changes size or another column changes.
    private func fitNameColumn() {
        guard let name = tableView.tableColumn(withIdentifier: FileColumn.name.identifier) else { return }
        // The table's own column edges include its spacing and insets.
        let right = tableView.tableColumns.indices.filter { !tableView.tableColumns[$0].isHidden }
            .map { tableView.rect(ofColumn: $0).maxX }.max() ?? 0
        let width = max(name.minWidth, floor(name.width - (right - scrollView.contentView.bounds.width)))
        if abs(name.width - width) > 0.5 { name.width = width }
    }

    @objc private func clipViewResized(_ note: Notification) { fitNameColumn() }

    @objc private func columnsChanged(_ note: Notification) {
        // A user resizing Name keeps that width until the pane changes size.
        if (note.userInfo?["NSTableColumn"] as? NSTableColumn)?.identifier != FileColumn.name.identifier { fitNameColumn() }
        let states = tableView.tableColumns.map { ColumnState(id: $0.identifier.rawValue, width: Double($0.width), hidden: $0.isHidden) }
        AppServices.shared.update { $0.columns = states }
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let column = tableView.tableColumns.first(where: { $0.identifier.rawValue == sender.representedObject as? String }) else { return }
        column.isHidden.toggle()
        columnsChanged(Notification(name: NSTableView.columnDidResizeNotification))
    }

    private func updateSortIndicator() {
        guard isViewLoaded, let column = FileColumn(sortKey: sortOrder.key) else { return }
        let wanted = [NSSortDescriptor(key: column.rawValue, ascending: sortOrder.ascending)]
        if tableView.sortDescriptors != wanted { tableView.sortDescriptors = wanted }
    }

    // MARK: Loading

    /// Lists `folder` in the background. `select` picks rows once loaded; `completion` gets the error, if any.
    func load(_ folder: URL, select: [URL]? = nil, completion: ((Error?) -> Void)? = nil) {
        let isNewFolder = folder != self.folder
        self.folder = folder
        generation += 1
        let gen = generation
        let hidden = AppServices.shared.settings.showHidden
        let previousSelection = isNewFolder ? [] : selectedURLs
        let started = ProcessInfo.processInfo.systemUptime
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try DirectoryReader.read(folder, includeHidden: hidden) }
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.generation else { return }
                switch result {
                case .success(let list):
                    self.loadError = nil
                    self.allItems = list
                case .failure(let error):
                    self.loadError = error
                    self.allItems = []
                }
                self.applyItems(keepSelection: false)
                let toSelect = select ?? previousSelection
                if !toSelect.isEmpty { self.select(toSelect, scroll: true) }
                else if isNewFolder { self.tableView.scrollRowToVisible(0) }
                if ProcessInfo.processInfo.environment["OKNO_TRACE"] != nil {
                    let ms = (ProcessInfo.processInfo.systemUptime - started) * 1000
                    FileHandle.standardError.write(Data(String(format: "okno: listed %d items in %.1f ms\n", self.items.count, ms).utf8))
                }
                completion?(self.loadError)
                let pending = self.onLoaded
                self.onLoaded = []
                pending.forEach { $0() }
            }
        }
    }

    /// Lists the folder again, keeping the selection.
    func reload(select: [URL]? = nil, then: (() -> Void)? = nil) {
        guard let folder else { return }
        if let then { onLoaded.append(then) }
        load(folder, select: select)
    }

    private func applyItems(keepSelection: Bool) {
        defer { delegate?.fileListItemsDidChange(self) }
        guard renaming == nil else { return }
        let selected = keepSelection ? selectedURLs : []
        items = FileSorter.sort(ListFilter.filter(allItems, query: filterQuery), by: sortOrder)
        tableView.reloadData()
        if !selected.isEmpty { select(selected, scroll: false) }
        delegate?.fileListSelectionDidChange(self)
    }

    // MARK: Selection

    var selectedItems: [FileItem] { tableView.selectedRowIndexes.compactMap { $0 < items.count ? items[$0] : nil } }
    var selectedURLs: [URL] { selectedItems.map(\.url) }

    func select(_ urls: [URL], scroll: Bool) {
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        let rows = IndexSet(items.indices.filter { paths.contains(items[$0].url.standardizedFileURL.path) })
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
        if scroll, let first = rows.first { tableView.scrollRowToVisible(first) }
    }

    func focus() { view.window?.makeFirstResponder(tableView) }

    @objc private func doubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        delegate?.fileList(self, open: [items[row]])
    }

    // MARK: Rename in place

    /// Turns the name cell into a text field with the name (without extension) selected.
    func beginRename(_ url: URL) {
        guard let row = items.firstIndex(where: { $0.url.standardizedFileURL == url.standardizedFileURL }),
              let col = tableView.tableColumns.firstIndex(where: { $0.identifier == FileColumn.name.identifier }) else { return }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        guard let cell = tableView.view(atColumn: col, row: row, makeIfNecessary: true) as? NameCellView else { return }
        let field = cell.label
        let item = items[row]
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.isBordered = true
        field.delegate = self
        renaming = (item, field, false)
        view.window?.makeFirstResponder(field)
        let base = item.isFolder ? item.name : (item.name as NSString).deletingPathExtension
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (base.isEmpty ? item.name : base).utf16.count)
    }

    var isRenaming: Bool { renaming != nil }

    private func endRename(commit: Bool) {
        guard let r = renaming else { return }
        renaming = nil
        r.field.isEditable = false
        r.field.isSelectable = false
        r.field.drawsBackground = false
        r.field.isBordered = false
        let newName = r.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        r.field.stringValue = r.item.name
        if commit, !newName.isEmpty, newName != r.item.name {
            delegate?.fileList(self, rename: r.item, to: newName)
        }
        applyItems(keepSelection: true)
    }

    // MARK: Quick Look

    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

// MARK: - Table data and cells

extension FileListViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let column = FileColumn(rawValue: tableColumn.identifier.rawValue), row < items.count else { return nil }
        let item = items[row]
        let dim = item.isHidden || dimmedURLs.contains(item.url)
        if column == .name {
            let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NameCellView ?? {
                let c = NameCellView()
                c.identifier = tableColumn.identifier
                return c
            }()
            if renaming?.field !== cell.label { cell.label.stringValue = item.name }
            cell.icon.image = IconCache.shared.icon(for: item)
            cell.icon.alphaValue = dim ? 0.5 : 1
            cell.label.textColor = dim ? .secondaryLabelColor : .labelColor
            cell.cloud.isHidden = !item.isCloudOnly
            return cell
        }
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? TextCellView ?? {
            let c = TextCellView(alignment: column == .size ? .right : .left)
            c.identifier = tableColumn.identifier
            return c
        }()
        switch column {
        case .modified: cell.label.stringValue = Formatters.date.string(from: item.modified)
        case .created: cell.label.stringValue = Formatters.date.string(from: item.created)
        case .type: cell.label.stringValue = FileTypes.displayName(for: item)
        case .size: cell.label.stringValue = item.isFolder || item.isPackage ? "" : Formatters.size(item.size)
        case .fileExtension: cell.label.stringValue = item.fileExtension
        case .name: break
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let d = tableView.sortDescriptors.first, let key = d.key, let column = FileColumn(rawValue: key) else { return }
        let order = FileSortOrder(key: column.sortKey, ascending: d.ascending)
        if order != sortOrder {
            sortOrder = order
            delegate?.fileListSortDidChange(self)
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        delegate?.fileListSelectionDidChange(self)
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        tableColumn?.identifier == FileColumn.name.identifier && row < items.count ? items[row].name : nil
    }

    // MARK: Drag source

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < items.count, renaming == nil else { return nil }
        return items[row].url as NSURL
    }

    // MARK: Drop target

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard let target = dropTarget(row: row, operation: dropOperation, tableView: tableView),
              let urls = info.fileURLs, !urls.isEmpty else { return [] }
        // Dropping items into the folder they are already in does nothing.
        if urls.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == target.standardizedFileURL }) { return [] }
        if urls.contains(where: { target.standardizedFileURL.path.hasPrefix($0.standardizedFileURL.path + "/") || target.standardizedFileURL == $0.standardizedFileURL }) { return [] }
        return info.fileOperation(for: urls, into: target) == .copy ? .copy : .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let target = dropTarget(row: row, operation: dropOperation, tableView: tableView),
              let urls = info.fileURLs, !urls.isEmpty else { return false }
        return delegate?.fileList(self, drop: urls, into: target, operation: info.fileOperation(for: urls, into: target)) ?? false
    }

    /// A folder row under the pointer, or else the current folder (the drop retargets to the whole list).
    private func dropTarget(row: Int, operation: NSTableView.DropOperation, tableView: NSTableView) -> URL? {
        if operation == .on, row >= 0, row < items.count, items[row].isFolder {
            return items[row].url
        }
        tableView.setDropRow(-1, dropOperation: .on)
        return folder
    }
}

// MARK: - Keys, menus, focus

extension FileListViewController: FileTableViewDelegate {
    func fileTable(_ table: FileTableView, handle key: ListKey) -> Bool {
        if key == .open {
            let selected = selectedItems
            guard !selected.isEmpty else { return true }
            delegate?.fileList(self, open: selected)
            return true
        }
        if key == .quickLook {
            guard !selectedItems.isEmpty else { return true }
            toggleQuickLook()
            return true
        }
        return delegate?.fileList(self, handle: key) ?? false
    }

    func fileTable(_ table: FileTableView, menuForRows rows: IndexSet) -> NSMenu? {
        delegate?.fileList(self, menuFor: rows.compactMap { $0 < items.count ? items[$0] : nil })
    }

    func fileTableDidBecomeFirstResponder(_ table: FileTableView) {
        delegate?.fileListDidActivate(self)
    }
}

extension FileListViewController: NSMenuDelegate {
    // The column header's menu: show or hide columns.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for column in tableView.tableColumns {
            guard column.identifier != FileColumn.name.identifier else { continue }
            let item = NSMenuItem(title: column.title, action: #selector(toggleColumn), keyEquivalent: "")
            item.target = self
            item.representedObject = column.identifier.rawValue
            item.state = column.isHidden ? .off : .on
            menu.addItem(item)
        }
    }
}

extension FileListViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard renaming != nil else { return false }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            renaming?.cancelled = true
            view.window?.makeFirstResponder(tableView)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let r = renaming, obj.object as? NSTextField === r.field else { return }
        endRename(commit: !r.cancelled)
        view.window?.makeFirstResponder(tableView)
    }
}

// MARK: - Quick Look data

extension FileListViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { selectedItems.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let selected = selectedItems
        return index < selected.count ? selected[index].url as NSURL : nil
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Arrow keys move the selection while the preview is open.
        if event.type == .keyDown { tableView.keyDown(with: event); return true }
        return false
    }
}
