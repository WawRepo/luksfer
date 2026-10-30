import AppKit
import LuksferCore

/// One Luksfer window: sidebar, one or two panes, the terminal panel and the status bar.
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    private let splitController = NSSplitViewController()
    let sidebar = SidebarViewController()
    private(set) var panes: [PaneViewController] = []
    private(set) var activeIndex = 0
    private(set) var twoPanes = false
    private let panesSplit = NSSplitView()
    private let mainSplit = NSSplitView()
    private let terminalContainer = NSView()
    private(set) var terminal: TerminalPanelController?
    private(set) var terminalOpen = false
    private var shellExited = false
    private var terminalHeight: CGFloat = 240
    private let terminalUndoManager = UndoManager()
    let statusBar = StatusBarView()
    private var mouseMonitor: Any?
    var toolbarButtons: [NSToolbarItem.Identifier: NSControl] = [:]
    var onClose: ((BrowserWindowController) -> Void)?

    var activePane: PaneViewController { panes[activeIndex] }
    var otherPane: PaneViewController { panes[1 - activeIndex] }

    init(state: WindowState?, folder: URL? = nil) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 640, height: 400)
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self

        let home = FileManager.default.homeDirectoryForCurrentUser
        let paneStates = state?.panes ?? []
        for i in 0..<2 {
            var start = i < paneStates.count ? URL(fileURLWithPath: paneStates[i].path, isDirectory: true) : home
            if i == 0, let folder { start = folder }
            if !FileManager.default.fileExists(atPath: start.path) { start = home }
            let pane = PaneViewController(folder: start, sort: i < paneStates.count ? paneStates[i].sort : FileSortOrder())
            pane.delegate = self
            panes.append(pane)
        }
        twoPanes = state?.twoPanes ?? false
        activeIndex = twoPanes ? min(max(state?.activePane ?? 0, 0), 1) : 0
        terminalHeight = CGFloat(state?.terminalHeight ?? 240)

        buildLayout(sidebarWidth: CGFloat(state?.sidebarWidth ?? 200))
        buildToolbar()
        if let frame = state?.frame {
            window.setFrame(NSRectFromString(frame), display: false)
        } else {
            window.setContentSize(NSSize(width: 1240, height: 780))
            window.center()
        }
        setTwoPanes(twoPanes, focus: false)
        setActive(activeIndex)
        // Keys work in the list from the start (not in the sidebar or the search box).
        window.initialFirstResponder = activePane.list.tableView

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.activatePane(at: event)
            return event
        }
        statusBar.onStop = { [weak self] in self?.stopOperation() }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(settingsChanged), name: .luksferSettingsChanged, object: nil)
        nc.addObserver(self, selector: #selector(cutChanged), name: .luksferCutChanged, object: nil)
        applyKeyMode()
        if state?.terminalOpen == true {
            DispatchQueue.main.async { self.openTerminal(at: self.activePane.folder, focus: false) }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) } }

    // MARK: Layout

    private func buildLayout(sidebarWidth: CGFloat) {
        sidebar.delegate = self
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 150
        sidebarItem.maximumThickness = 360
        sidebarItem.canCollapse = true

        let content = NSViewController()
        let contentView = NSView()
        content.view = contentView

        panesSplit.isVertical = true
        panesSplit.dividerStyle = .thin
        for pane in panes {
            content.addChild(pane)
            panesSplit.addArrangedSubview(pane.view)
        }
        mainSplit.isVertical = false
        mainSplit.dividerStyle = .thin
        mainSplit.delegate = self
        mainSplit.addArrangedSubview(panesSplit)
        mainSplit.addArrangedSubview(terminalContainer)
        terminalContainer.isHidden = true
        mainSplit.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        mainSplit.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        for v in [mainSplit, statusBar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }
        NSLayoutConstraint.activate([
            mainSplit.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor),
            mainSplit.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainSplit.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.topAnchor.constraint(equalTo: mainSplit.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        splitController.addSplitViewItem(sidebarItem)
        splitController.addSplitViewItem(NSSplitViewItem(viewController: content))
        window?.contentViewController = splitController
        splitController.splitView.setPosition(sidebarWidth, ofDividerAt: 0)
    }

    // MARK: Panes

    func setTwoPanes(_ on: Bool, focus: Bool = true) {
        twoPanes = on
        panes[1].view.isHidden = !on
        panesSplit.adjustSubviews()
        if on { panesSplit.setPosition(panesSplit.bounds.width / 2, ofDividerAt: 0) }
        if !on && activeIndex == 1 { setActive(0) }
        for pane in panes { pane.showsActiveMark = on }
        (toolbarButtons[.panes] as? NSSegmentedControl)?.selectedSegment = on ? 1 : 0
        if focus { activePane.list.focus() }
    }

    func setActive(_ index: Int) {
        guard index < panes.count else { return }
        let changed = index != activeIndex
        activeIndex = index
        for (i, pane) in panes.enumerated() { pane.isActive = i == index }
        paneChanged()
        if changed, terminalOpen, terminal?.followEnabled == true { terminal?.changeDirectory(to: activePane.folder) }
    }

    private func activatePane(at event: NSEvent) {
        guard event.window === window else { return }
        for (i, pane) in panes.enumerated() where !pane.view.isHidden {
            let p = pane.view.convert(event.locationInWindow, from: nil)
            if pane.view.bounds.contains(p) {
                if i != activeIndex { setActive(i) }
                return
            }
        }
    }

    @objc func switchPane(_ sender: Any?) {
        guard twoPanes else { return }
        setActive(1 - activeIndex)
        activePane.list.focus()
        if activePane.list.tableView.selectedRow < 0, !activePane.list.items.isEmpty {
            activePane.list.tableView.selectRowIndexes([0], byExtendingSelection: false)
        }
    }

    /// Title, sidebar highlight, status bar and toolbar follow the active pane.
    private func paneChanged() {
        let folder = activePane.folder
        window?.title = folder.displayName
        window?.representedURL = folder
        sidebar.highlight(folder)
        updateStatus()
        updateToolbar()
        updateFreeSpace(for: folder)
    }

    func updateStatus() {
        let list = activePane.list
        let count = list.items.count
        let selected = list.selectedItems
        var text = count == 1 ? "1 item" : "\(count) items"
        if !list.filterQuery.isEmpty { text += " found" }
        if !selected.isEmpty {
            let bytes = selected.filter { !$0.isFolder }.reduce(Int64(0)) { $0 + $1.size }
            text += " · \(selected.count) selected"
            if bytes > 0 { text += " (\(Formatters.size(bytes)))" }
        }
        statusBar.infoLabel.stringValue = text
    }

    private func updateFreeSpace(for folder: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let v = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let text = v?.volumeAvailableCapacityForImportantUsage.map { "\(Formatters.size($0)) free" } ?? ""
            DispatchQueue.main.async { self?.statusBar.freeLabel.stringValue = text }
        }
    }

    // MARK: Terminal

    func openTerminal(at folder: URL, focus: Bool = true) {
        if terminal == nil {
            let t = TerminalPanelController(startFolder: folder, shellFilesFolder: AppServices.shared.store.fileURL
                .deletingLastPathComponent().appendingPathComponent("shell", isDirectory: true))
            t.delegate = self
            t.followEnabled = AppServices.shared.settings.terminalFollow
            terminal = t
            let v = t.view
            v.translatesAutoresizingMaskIntoConstraints = false
            terminalContainer.addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
                v.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
                v.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
            ])
        } else if shellExited {
            shellExited = false
            terminal?.restartShell(in: folder)
        } else {
            terminal?.changeDirectory(to: folder)
        }
        if !terminalOpen {
            terminalOpen = true
            terminalContainer.isHidden = false
            mainSplit.adjustSubviews()
            mainSplit.setPosition(max(120, mainSplit.bounds.height - terminalHeight), ofDividerAt: 0)
        }
        (toolbarButtons[.terminal] as? NSButton)?.state = .on
        if focus { terminal?.focusTerminal() }
    }

    func closeTerminal() {
        guard terminalOpen else { return }
        terminalHeight = terminalContainer.frame.height
        terminalOpen = false
        terminalContainer.isHidden = true
        mainSplit.adjustSubviews()
        (toolbarButtons[.terminal] as? NSButton)?.state = .off
        activePane.list.focus()
    }

    @objc func toggleTerminal(_ sender: Any?) {
        if terminalOpen {
            // ⌃` from the terminal closes it; from a pane it moves focus there first if hidden.
            closeTerminal()
        } else {
            openTerminal(at: activePane.folder)
        }
    }

    @objc func openInTerminalApp(_ sender: Any?) {
        let folder = selectedFolderOrCurrent()
        let app = TerminalApp(rawValue: AppServices.shared.settings.terminalApp) ?? .terminal
        do { try TerminalAppLauncher.open(folder, in: app) } catch { showError(error) }
    }

    /// The selected folder when exactly one folder is selected, else the pane's folder.
    func selectedFolderOrCurrent() -> URL {
        let sel = activePane.list.selectedItems
        if sel.count == 1, sel[0].isFolder { return sel[0].url }
        return activePane.folder
    }

    /// Shows the error as a sheet; `then` runs when the user closes it.
    func showError(_ error: Error, then: (() -> Void)? = nil) {
        guard let window else { then?(); return }
        if ProcessInfo.processInfo.environment["LUKSFER_SELFTEST"] != nil {
            FileHandle.standardError.write(Data("selftest: error shown: \(error.localizedDescription)\n".utf8))
        }
        NSAlert(error: error).beginSheetModal(for: window) { _ in then?() }
    }

    // MARK: State

    func state() -> WindowState {
        var s = WindowState(panes: panes.map { PaneState(path: $0.folder.path, sort: $0.list.sortOrder) })
        s.frame = window.map { NSStringFromRect($0.frame) }
        s.twoPanes = twoPanes
        s.activePane = activeIndex
        s.terminalOpen = terminalOpen
        s.terminalHeight = Double(terminalOpen ? terminalContainer.frame.height : terminalHeight)
        s.sidebarWidth = Double(sidebar.view.frame.width)
        return s
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }

    /// Undo and Redo change files. While the terminal has focus, or a file job still runs, they get
    /// an empty stack, so ⌘Z never undoes a file action by surprise or an older step too early.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        terminalHasFocus || FileActions.shared.isBusy ? terminalUndoManager : AppServices.shared.undoManager
    }

    var terminalHasFocus: Bool { window?.firstResponder is ShellTerminalView }

    func windowDidBecomeKey(_ notification: Notification) { updateToolbar() }

    @objc func stopOperation() { FileActions.shared.cancelCurrent() }

    private var lastShowHidden: Bool?

    @objc private func settingsChanged() {
        let hidden = AppServices.shared.settings.showHidden
        if lastShowHidden != nil && lastShowHidden != hidden { panes.forEach { $0.reload() } }
        lastShowHidden = hidden
        applyKeyMode()
    }

    private func applyKeyMode() {
        lastShowHidden = lastShowHidden ?? AppServices.shared.settings.showHidden
        let finder = AppServices.shared.settings.keyMode == .finder
        panes.forEach { $0.list.tableView.enterRenames = finder }
    }

    @objc private func cutChanged() {
        let cut = FileActions.shared.pendingCut
        panes.forEach { $0.list.dimmedURLs = cut }
        updateToolbar()   // Paste turns on after ⌘C or ⌘X
    }
}

// MARK: - Pane events

extension BrowserWindowController: PaneDelegate {
    func paneDidBecomeActive(_ pane: PaneViewController) {
        if let i = panes.firstIndex(where: { $0 === pane }), i != activeIndex { setActive(i) }
    }

    func paneDidChangeFolder(_ pane: PaneViewController) {
        guard pane === activePane else { return }
        paneChanged()
        if terminalOpen, terminal?.followEnabled == true { terminal?.changeDirectory(to: pane.folder) }
    }

    func paneSelectionDidChange(_ pane: PaneViewController) {
        if pane === activePane { updateStatus(); updateToolbar() }
    }

    func paneSortDidChange(_ pane: PaneViewController) {}

    func paneOpenTerminal(_ pane: PaneViewController) {
        openTerminal(at: pane.folder)
    }

    func pane(_ pane: PaneViewController, handle key: ListKey) -> Bool {
        switch key {
        case .switchPane: switchPane(nil); return twoPanes
        case .rename: renameSelection(nil); return true
        case .trash: moveToTrash(nil); return true
        case .deleteNow: deleteImmediately(nil); return true
        default: return false
        }
    }

    func pane(_ pane: PaneViewController, menuFor items: [FileItem]) -> NSMenu? {
        ContextMenus.menu(for: items, in: pane, window: self)
    }

    func pane(_ pane: PaneViewController, rename item: FileItem, to name: String) {
        // A failed rename opens the name again with what the user typed.
        FileActions.shared.rename(item.url, to: name, in: self) { [weak pane] in
            pane?.list.beginRename(item.url, typed: name)
        }
    }

    func pane(_ pane: PaneViewController, drop urls: [URL], into folder: URL, operation: DropOperation) -> Bool {
        FileActions.shared.transfer(urls, into: folder, operation: operation, in: self)
        return true
    }
}

// MARK: - Sidebar events

extension BrowserWindowController: SidebarDelegate {
    func sidebar(_ sidebar: SidebarViewController, open url: URL) {
        activePane.navigate(to: url)
    }

    func sidebar(_ sidebar: SidebarViewController, openInOtherPane url: URL) {
        if !twoPanes { setTwoPanes(true, focus: false) }
        otherPane.navigate(to: url)
        setActive(1 - activeIndex)
    }

    func sidebar(_ sidebar: SidebarViewController, drop urls: [URL], into folder: URL, operation: DropOperation) -> Bool {
        FileActions.shared.transfer(urls, into: folder, operation: operation, in: self)
        return true
    }
}

// MARK: - Terminal events

extension BrowserWindowController: TerminalPanelDelegate {
    func terminalPanel(_ panel: TerminalPanelController, didChangeDirectory folder: URL) {
        guard panel.followEnabled, folder.standardizedFileURL != activePane.folder.standardizedFileURL else { return }
        activePane.navigate(to: folder)
    }

    func terminalPanelShellDidExit(_ panel: TerminalPanelController) {
        shellExited = true
        closeTerminal()
    }
    func terminalPanelWantsClose(_ panel: TerminalPanelController) { closeTerminal() }
    func terminalPanelOpenInTerminalApp(_ panel: TerminalPanelController) {
        let app = TerminalApp(rawValue: AppServices.shared.settings.terminalApp) ?? .terminal
        do { try TerminalAppLauncher.open(panel.currentFolder ?? activePane.folder, in: app) } catch { showError(error) }
    }

    func terminalPanel(_ panel: TerminalPanelController, didSetFollow enabled: Bool) {
        AppServices.shared.update { $0.terminalFollow = enabled }
        if enabled { panel.changeDirectory(to: activePane.folder) }
    }
}

extension BrowserWindowController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        splitView === mainSplit ? max(proposedMinimumPosition, 140) : proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        splitView === mainSplit ? min(proposedMaximumPosition, splitView.bounds.height - 90) : proposedMaximumPosition
    }
}
