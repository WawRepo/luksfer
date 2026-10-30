import AppKit
import OknoCore

/// Right-click menus for files, folders and empty space (PRD §6.5).
enum ContextMenus {
    static func menu(for items: [FileItem], in pane: PaneViewController, window: BrowserWindowController) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            menu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: ""))
        }
        if items.isEmpty {
            add("Copy Path", #selector(BrowserWindowController.copyPath(_:)))
            add("Pin This Folder", #selector(BrowserWindowController.pinToFavorites(_:)))
            menu.addItem(.separator())
            add("Open in Terminal", #selector(BrowserWindowController.openInTerminal(_:)))
            add("Open in Terminal App", #selector(BrowserWindowController.openInTerminalApp(_:)))
        } else {
            add("Open", #selector(BrowserWindowController.openSelection(_:)))
            add("Open in Other Pane", #selector(BrowserWindowController.openInOtherPane(_:)))
            add("Quick Look", #selector(BrowserWindowController.quickLook(_:)))
            menu.addItem(.separator())
            add("Copy Path", #selector(BrowserWindowController.copyPath(_:)))
            add("Open in Terminal", #selector(BrowserWindowController.openInTerminal(_:)))
            add("Open in Terminal App", #selector(BrowserWindowController.openInTerminalApp(_:)))
        }
        return menu
    }
}
