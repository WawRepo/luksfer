import AppKit
import LuksferCore

// Menu and toolbar actions. They reach the window controller through the responder chain and
// act on the active pane.
extension BrowserWindowController: NSMenuItemValidation {
    // MARK: Go

    @objc func goBack(_ sender: Any?) { activePane.goBack() }
    @objc func goForward(_ sender: Any?) { activePane.goForward() }
    @objc func goUp(_ sender: Any?) { activePane.goUp() }
    @objc func goHome(_ sender: Any?) { go(FileManager.default.homeDirectoryForCurrentUser) }
    @objc func goDesktop(_ sender: Any?) { go(home("Desktop")) }
    @objc func goDocuments(_ sender: Any?) { go(home("Documents")) }
    @objc func goDownloads(_ sender: Any?) { go(home("Downloads")) }
    @objc func goApplications(_ sender: Any?) { go(URL(fileURLWithPath: "/Applications", isDirectory: true)) }

    private func home(_ name: String) -> URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name, isDirectory: true) }

    private func go(_ url: URL) {
        activePane.navigate(to: url)
        activePane.list.focus()
    }

    @objc func editPath(_ sender: Any?) { activePane.pathBar.beginEditing() }
    @objc func copyPath(_ sender: Any?) { activePane.copyPath() }
    @objc func focusSearch(_ sender: Any?) { activePane.focusSearch() }
    @objc func reloadFolder(_ sender: Any?) { panes.forEach { $0.reload() } }

    // MARK: View

    @objc func toggleHiddenFiles(_ sender: Any?) {
        AppServices.shared.update { $0.showHidden.toggle() }
    }

    @objc func setOnePane(_ sender: Any?) { setTwoPanes(false) }
    @objc func setTwoPanesAction(_ sender: Any?) { setTwoPanes(true) }
    @objc func togglePanes(_ sender: Any?) { setTwoPanes(!twoPanes) }

    @objc func panesSegmentChanged(_ sender: NSSegmentedControl) { setTwoPanes(sender.selectedSegment == 1) }

    @objc func swapPanes(_ sender: Any?) {
        guard twoPanes else { return }
        let a = panes[0].folder, b = panes[1].folder
        panes[0].navigate(to: b)
        panes[1].navigate(to: a)
    }

    @objc func sameFolderInBoth(_ sender: Any?) {
        if !twoPanes { setTwoPanes(true, focus: false) }
        otherPane.navigate(to: activePane.folder)
    }

    // MARK: Open

    @objc func openSelection(_ sender: Any?) {
        let items = activePane.list.selectedItems
        guard !items.isEmpty else { return }
        activePane.fileList(activePane.list, open: items)
    }

    @objc func openInOtherPane(_ sender: Any?) {
        let target = selectedFolderOrCurrent()
        if !twoPanes { setTwoPanes(true, focus: false) }
        otherPane.navigate(to: target)
    }

    @objc func quickLook(_ sender: Any?) { activePane.list.toggleQuickLook() }

    /// On a search result: opens the folder it is in and selects it.
    @objc func openContainingFolder(_ sender: Any?) {
        guard let item = activePane.list.selectedItems.first else { return }
        activePane.navigate(to: item.url.deletingLastPathComponent(), select: [item.url])
        activePane.list.focus()
    }

    @objc func openInTerminal(_ sender: Any?) { openTerminal(at: selectedFolderOrCurrent()) }

    @objc func pinToFavorites(_ sender: Any?) {
        let folders = activePane.list.selectedItems.filter(\.isFolder).map(\.url)
        let targets = folders.isEmpty ? [activePane.folder] : folders
        if targets.allSatisfy(AppServices.shared.isFavorite) {
            targets.forEach(AppServices.shared.unpin)
        } else {
            AppServices.shared.pin(targets)
        }
    }


    // MARK: Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // While a text field edits (rename, path, search) or the terminal has focus, file actions
        // stay off so their keys (⌘⌫, ⌘X, ⌘D …) go to the text or the shell.
        let editingText = window?.firstResponder is NSText || terminalHasFocus
        let selection = activePane.list.selectedItems
        switch item.action {
        case #selector(goBack(_:)): return activePane.canGoBack
        case #selector(goForward(_:)): return activePane.history.canGoForward
        case #selector(goUp(_:)): return !activePane.folder.isRootFolder
        case #selector(toggleHiddenFiles(_:)):
            item.state = AppServices.shared.settings.showHidden ? .on : .off
            return true
        case #selector(togglePanes(_:)):
            item.state = twoPanes ? .on : .off
            return true
        case #selector(setOnePane(_:)):
            item.state = twoPanes ? .off : .on
            return true
        case #selector(setTwoPanesAction(_:)):
            item.state = twoPanes ? .on : .off
            return true
        case #selector(swapPanes(_:)): return twoPanes
        case #selector(toggleTerminal(_:)):
            item.title = terminalOpen ? "Hide Terminal" : "Show Terminal"
            return true
        case #selector(openSelection(_:)), #selector(quickLook(_:)):
            return !editingText && !selection.isEmpty
        case #selector(renameSelection(_:)), #selector(openContainingFolder(_:)):
            return !editingText && selection.count == 1
        case #selector(moveToTrash(_:)), #selector(deleteImmediately(_:)), #selector(cut(_:)), #selector(copy(_:)),
             #selector(duplicateItems(_:)), #selector(compressItems(_:)):
            return !editingText && !selection.isEmpty
        case #selector(paste(_:)), #selector(pasteMove(_:)):
            return !editingText && FileClipboard.hasFiles
        case #selector(pasteInto(_:)):
            return FileClipboard.hasFiles
        case #selector(newFolder(_:)), #selector(newTextFile(_:)), #selector(newMarkdownFile(_:)), #selector(getInfo(_:)):
            return !editingText
        case #selector(sortBy(_:)):
            let order = activePane.list.sortOrder
            let keys = SortKey.allCases
            if item.tag < keys.count { item.state = order.key == keys[item.tag] ? .on : .off }
            else { item.state = (item.tag == 100) == order.ascending ? .on : .off }
            return true
        case #selector(pinToFavorites(_:)):
            let folders = selection.filter(\.isFolder).map(\.url)
            let targets = folders.isEmpty ? [activePane.folder] : folders
            item.title = targets.allSatisfy(AppServices.shared.isFavorite) ? "Unpin from Favorites" : "Pin to Favorites"
            return !editingText
        case #selector(switchPane(_:)): return twoPanes
        case #selector(addNetworkDrive(_:)): return !terminalHasFocus   // ⌘K clears a terminal
        default: return true
        }
    }
}

// MARK: - Toolbar

extension NSToolbarItem.Identifier {
    static let newItem = Self("luksfer.new")
    static let cut = Self("luksfer.cut")
    static let copy = Self("luksfer.copy")
    static let paste = Self("luksfer.paste")
    static let rename = Self("luksfer.rename")
    static let trash = Self("luksfer.trash")
    static let panes = Self("luksfer.panes")
    static let terminal = Self("luksfer.terminal")
    static let terminalApp = Self("luksfer.terminalApp")
}

extension BrowserWindowController: NSToolbarDelegate {
    func buildToolbar() {
        let toolbar = NSToolbar(identifier: "LuksferBrowser")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .newItem, .cut, .copy, .paste, .rename, .trash,
         .flexibleSpace, .panes, .terminal, .terminalApp]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case .newItem:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.image = .symbol("plus", "New", size: 14, weight: .medium)
            item.label = "New"
            item.title = "New"
            item.toolTip = "New folder or file"
            item.showsIndicator = true
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "New Folder", action: #selector(newFolder(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "New Text File", action: #selector(newTextFile(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "New Markdown File", action: #selector(newMarkdownFile(_:)), keyEquivalent: ""))
            item.menu = menu
            return item
        // In a narrow window Cut, Copy and Paste go into the » menu first (they have keys);
        // the pane switch and Terminal stay.
        case .cut: return button(id, "Cut", "scissors", #selector(cut(_:)), "Cut (⌘X)", priority: .low)
        case .copy: return button(id, "Copy", "doc.on.doc", #selector(copy(_:)), "Copy (⌘C)", priority: .low)
        case .paste: return button(id, "Paste", "doc.on.clipboard", #selector(paste(_:)), "Paste (⌘V)", priority: .low)
        case .rename: return button(id, "Rename", "pencil", #selector(renameSelection(_:)), "Rename (F2)")
        case .trash: return button(id, "Trash", "trash", #selector(moveToTrash(_:)), "Move to Trash (⌘⌫)")
        case .terminal:
            let item = button(id, "Terminal", "apple.terminal", #selector(toggleTerminal(_:)), "Terminal (⌃`)", priority: .high)
            (item.view as? NSButton)?.setButtonType(.pushOnPushOff)
            return item
        case .terminalApp: return button(id, "Terminal app", "arrow.up.forward.app", #selector(openInTerminalApp(_:)), "Open this folder in your terminal app (⌥⌘T)")
        case .panes:
            let seg = NSSegmentedControl(images: [.symbol("rectangle", "One pane", size: 14), .symbol("rectangle.split.2x1", "Two panes", size: 14)],
                                         trackingMode: .selectOne, target: self, action: #selector(panesSegmentChanged(_:)))
            seg.setToolTip("One pane", forSegment: 0)
            seg.setToolTip("Two panes", forSegment: 1)
            seg.setLabel("", forSegment: 0)
            seg.selectedSegment = twoPanes ? 1 : 0
            seg.setAccessibilityLabel("Panes")
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = seg
            item.label = "Panes"
            item.visibilityPriority = .high
            toolbarButtons[id] = seg
            return item
        default:
            return nil
        }
    }

    private func button(_ id: NSToolbarItem.Identifier, _ title: String, _ symbol: String, _ action: Selector, _ tip: String,
                        priority: NSToolbarItem.VisibilityPriority = .standard) -> NSToolbarItem {
        let b = NSButton(title: title, image: .symbol(symbol, title, size: 13), target: nil, action: action)
        b.imagePosition = .imageLeading
        b.bezelStyle = .toolbar
        b.toolTip = tip
        b.setAccessibilityLabel(title)
        let item = NSToolbarItem(itemIdentifier: id)
        item.view = b
        item.label = title
        item.toolTip = tip
        item.visibilityPriority = priority
        toolbarButtons[id] = b
        return item
    }

    /// Enables toolbar buttons for the current selection and clipboard.
    func updateToolbar() {
        let hasSelection = !activePane.list.selectedItems.isEmpty
        for id in [NSToolbarItem.Identifier.cut, .copy, .rename, .trash] {
            toolbarButtons[id]?.isEnabled = hasSelection
        }
        toolbarButtons[.rename]?.isEnabled = activePane.list.selectedItems.count == 1
        toolbarButtons[.paste]?.isEnabled = FileClipboard.hasFiles
        (toolbarButtons[.terminal] as? NSButton)?.state = terminalOpen ? .on : .off
    }
}

/// Files on the general pasteboard (for Paste), and the cut marker (PRD §6.6).
enum FileClipboard {
    static let cutType = NSPasteboard.PasteboardType("io.github.wawrepo.luksfer.cut")
    /// The general pasteboard. Self-test runs use a private one, so the user's clipboard stays as it is.
    static let pasteboard: NSPasteboard = TestSwitches.isSelfTest()
        ? NSPasteboard(name: .init("io.github.wawrepo.luksfer.selftest")) : .general

    static var hasFiles: Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }
}
