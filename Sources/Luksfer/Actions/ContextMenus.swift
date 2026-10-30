import AppKit
import LuksferCore

/// Right-click menus for a file, a folder and empty space (PRD §6.5). New folder and New text file
/// are on every menu: next to a file, inside or next to a folder (in a New submenu, like
/// Explorer), or in the current folder. Items show the main menu's key shortcut for the same action.
enum ContextMenus {
    typealias W = BrowserWindowController

    static func menu(for items: [FileItem], in pane: PaneViewController, window: W) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = true
        if items.isEmpty {
            emptySpace(menu, folder: pane.folder, pane: pane)
        } else if items.count == 1, items[0].isFolder {
            folder(menu, items[0], pane: pane)
        } else {
            files(menu, items, pane: pane)
        }
        return menu
    }

    // MARK: Menus

    private static func files(_ menu: NSMenu, _ items: [FileItem], pane: PaneViewController) {
        let single = items.count == 1 ? items[0] : nil
        add(menu, "Open", #selector(W.openSelection(_:)), symbol: "arrow.up.forward.square")
        if let single { menu.addItem(openWith(single.url)) }
        add(menu, "Quick Look", #selector(W.quickLook(_:)), symbol: "eye")
        menu.addItem(.separator())
        add(menu, "Cut", #selector(W.cut(_:)), symbol: "scissors")
        add(menu, "Copy", #selector(W.copy(_:)), symbol: "doc.on.doc")
        add(menu, "Copy Path", #selector(W.copyPath(_:)), symbol: "link")
        menu.addItem(.separator())
        if single != nil { add(menu, "Rename", #selector(W.renameSelection(_:)), symbol: "pencil") }
        add(menu, "Duplicate", #selector(W.duplicateItems(_:)), symbol: "plus.square.on.square")
        add(menu, "Compress", #selector(W.compressItems(_:)), symbol: "archivebox")
        add(menu, "Move to Trash", #selector(W.moveToTrash(_:)), symbol: "trash")
        menu.addItem(.separator())
        add(menu, "New Folder Here", #selector(W.newFolder(_:)), symbol: "folder.badge.plus", target: pane.folder)
        add(menu, "New Text File Here", #selector(W.newTextFile(_:)), symbol: "doc.badge.plus", target: pane.folder)
        menu.addItem(.separator())
        add(menu, "Open in Terminal", #selector(W.openInTerminal(_:)), symbol: "apple.terminal")
        add(menu, "Open in Terminal App", #selector(W.openInTerminalApp(_:)), symbol: "arrow.up.forward.app")
        menu.addItem(.separator())
        add(menu, "Get Info", #selector(W.getInfo(_:)), symbol: "info.circle")
    }

    private static func folder(_ menu: NSMenu, _ item: FileItem, pane: PaneViewController) {
        add(menu, "Open", #selector(W.openSelection(_:)), symbol: "folder")
        add(menu, "Open in Other Pane", #selector(W.openInOtherPane(_:)), symbol: "rectangle.split.2x1")
        let pinned = AppServices.shared.isFavorite(item.url)
        add(menu, pinned ? "Unpin from Favorites" : "Pin to Favorites", #selector(W.pinToFavorites(_:)), symbol: pinned ? "star.slash" : "star")
        menu.addItem(.separator())
        add(menu, "Cut", #selector(W.cut(_:)), symbol: "scissors")
        add(menu, "Copy", #selector(W.copy(_:)), symbol: "doc.on.doc")
        add(menu, "Paste Into Folder", #selector(W.pasteInto(_:)), symbol: "doc.on.clipboard", target: item.url)
        add(menu, "Copy Path", #selector(W.copyPath(_:)), symbol: "link")
        menu.addItem(.separator())
        add(menu, "Rename", #selector(W.renameSelection(_:)), symbol: "pencil")
        add(menu, "Duplicate", #selector(W.duplicateItems(_:)), symbol: "plus.square.on.square")
        add(menu, "Compress", #selector(W.compressItems(_:)), symbol: "archivebox")
        add(menu, "Move to Trash", #selector(W.moveToTrash(_:)), symbol: "trash")
        menu.addItem(.separator())
        menu.addItem(newItems(inside: item.url, nextTo: pane.folder))
        menu.addItem(.separator())
        add(menu, "Open in Terminal", #selector(W.openInTerminal(_:)), symbol: "apple.terminal")
        add(menu, "Open in Terminal App", #selector(W.openInTerminalApp(_:)), symbol: "arrow.up.forward.app")
        menu.addItem(.separator())
        add(menu, "Get Info", #selector(W.getInfo(_:)), symbol: "info.circle")
    }

    private static func emptySpace(_ menu: NSMenu, folder: URL, pane: PaneViewController) {
        add(menu, "New Folder", #selector(W.newFolder(_:)), symbol: "folder.badge.plus", target: folder)
        add(menu, "New Text File", #selector(W.newTextFile(_:)), symbol: "doc.badge.plus", target: folder)
        add(menu, "New Markdown File", #selector(W.newMarkdownFile(_:)), symbol: "doc.richtext", target: folder)
        menu.addItem(.separator())
        add(menu, "Paste", #selector(W.paste(_:)), symbol: "doc.on.clipboard")
        add(menu, "Copy Path", #selector(W.copyPath(_:)), symbol: "link")
        let pinned = AppServices.shared.isFavorite(folder)
        add(menu, pinned ? "Unpin This Folder" : "Pin This Folder", #selector(W.pinToFavorites(_:)), symbol: pinned ? "star.slash" : "star")
        menu.addItem(.separator())
        add(menu, "Open in Terminal", #selector(W.openInTerminal(_:)), symbol: "apple.terminal")
        add(menu, "Open in Terminal App", #selector(W.openInTerminalApp(_:)), symbol: "arrow.up.forward.app")
        menu.addItem(.separator())
        menu.addItem(sortBy())
        menu.addItem(view())
        menu.addItem(.separator())
        add(menu, "Get Info", #selector(W.getInfo(_:)), symbol: "info.circle")
    }

    // MARK: Submenus

    /// "New ▸" on a folder: a new folder or text file inside it, or next to it.
    private static func newItems(inside folder: URL, nextTo parent: URL) -> NSMenuItem {
        let item = NSMenuItem(title: "New", action: nil, keyEquivalent: "")
        item.image = .symbol("plus.circle", nil)
        let sub = NSMenu()
        // ⇧⌘N and ⌥⌘N make items in the pane's folder, so only "next to it" shows them.
        add(sub, "New Folder Inside", #selector(W.newFolder(_:)), symbol: "folder.badge.plus", target: folder, shortcut: false)
        add(sub, "New Text File Inside", #selector(W.newTextFile(_:)), symbol: "doc.badge.plus", target: folder, shortcut: false)
        sub.addItem(.separator())
        add(sub, "New Folder Next to It", #selector(W.newFolder(_:)), symbol: "folder.badge.plus", target: parent)
        add(sub, "New Text File Next to It", #selector(W.newTextFile(_:)), symbol: "doc.badge.plus", target: parent)
        item.submenu = sub
        return item
    }

    private static func openWith(_ url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        item.image = .symbol("square.grid.2x2", nil)
        let sub = NSMenu()
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: url)
        for app in apps.prefix(20) {
            var name = FileManager.default.displayName(atPath: app.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            let i = NSMenuItem(title: app == defaultApp ? "\(name) (default)" : name, action: #selector(W.openWith(_:)), keyEquivalent: "")
            i.representedObject = app
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            i.image = icon
            if app == defaultApp { sub.insertItem(i, at: 0) } else { sub.addItem(i) }
        }
        if apps.isEmpty { sub.addItem(NSMenuItem(title: "No app found", action: nil, keyEquivalent: "")) }
        item.submenu = sub
        return item
    }

    private static func sortBy() -> NSMenuItem {
        let item = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
        item.image = .symbol("arrow.up.arrow.down", nil)
        let sub = NSMenu()
        for (i, key) in SortKey.allCases.enumerated() {
            let title = FileColumn(sortKey: key)?.title ?? key.rawValue
            let m = NSMenuItem(title: title, action: #selector(W.sortBy(_:)), keyEquivalent: "")
            m.tag = i
            sub.addItem(m)
        }
        sub.addItem(.separator())
        for (tag, title) in [(100, "Ascending"), (101, "Descending")] {
            let m = NSMenuItem(title: title, action: #selector(W.sortBy(_:)), keyEquivalent: "")
            m.tag = tag
            sub.addItem(m)
        }
        item.submenu = sub
        return item
    }

    private static func view() -> NSMenuItem {
        let item = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        item.image = .symbol("eye", nil)
        let sub = NSMenu()
        sub.addItem(NSMenuItem(title: "Show Hidden Files", action: #selector(W.toggleHiddenFiles(_:)), keyEquivalent: ""))
        sub.addItem(NSMenuItem(title: "Two Panes", action: #selector(W.togglePanes(_:)), keyEquivalent: ""))
        sub.addItem(NSMenuItem(title: "Reload", action: #selector(W.reloadFolder(_:)), keyEquivalent: ""))
        item.submenu = sub
        return item
    }

    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector, symbol: String, target: URL? = nil,
                            shortcut: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = .symbol(symbol, nil)
        item.representedObject = target
        if shortcut, let main = NSApp.mainMenu, let same = menuItem(for: action, in: main) {
            item.keyEquivalent = same.keyEquivalent
            item.keyEquivalentModifierMask = same.keyEquivalentModifierMask
        }
        menu.addItem(item)
    }

    /// The main menu item with a key shortcut for `action`, if there is one.
    private static func menuItem(for action: Selector, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.action == action, !item.keyEquivalent.isEmpty { return item }
            if let sub = item.submenu, let found = menuItem(for: action, in: sub) { return found }
        }
        return nil
    }
}
