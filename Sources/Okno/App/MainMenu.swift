import AppKit

/// The menu bar. Items target the first responder; the window controller handles them.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("Okno", [
            item("About Okno", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
            .separator(),
            item("Hide Okno", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Okno", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("File", [
            item("New Window", #selector(AppDelegate.newWindow(_:)), "n"),
            item("New Folder", sel("newFolder:"), "n", [.command, .shift]),
            item("New Text File", sel("newTextFile:"), "n", [.command, .option]),
            item("New Markdown File", sel("newMarkdownFile:")),
            .separator(),
            item("Open", #selector(BrowserWindowController.openSelection(_:)), "o"),
            item("Open in Other Pane", #selector(BrowserWindowController.openInOtherPane(_:))),
            item("Open in Terminal", #selector(BrowserWindowController.openInTerminal(_:))),
            item("Open in Terminal App", #selector(BrowserWindowController.openInTerminalApp(_:)), "t", [.command, .option]),
            item("Quick Look", #selector(BrowserWindowController.quickLook(_:)), "y"),
            .separator(),
            item("Rename", #selector(BrowserWindowController.renameSelection(_:)), functionKey(NSF2FunctionKey), []),
            item("Duplicate", sel("duplicateItems:"), "d"),
            item("Compress", sel("compressItems:")),
            item("Get Info", sel("getInfo:"), "i"),
            item("Pin to Favorites", #selector(BrowserWindowController.pinToFavorites(_:)), "t", [.command, .control]),
            .separator(),
            item("Move to Trash", #selector(BrowserWindowController.moveToTrash(_:)), "\u{8}"),
            item("Delete Immediately…", #selector(BrowserWindowController.deleteImmediately(_:)), "\u{8}", [.command, .option]),
            .separator(),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Move Here", sel("pasteMove:"), "v", [.command, .option]),
            item("Copy Path", #selector(BrowserWindowController.copyPath(_:)), "c", [.command, .option]),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Search This Folder", #selector(BrowserWindowController.focusSearch(_:)), "f"),
        ]))
        main.addItem(submenu("View", [
            item("One Pane", #selector(BrowserWindowController.setOnePane(_:)), "1", [.command, .option]),
            item("Two Panes", #selector(BrowserWindowController.setTwoPanesAction(_:)), "2", [.command, .option]),
            item("Switch Pane", #selector(BrowserWindowController.switchPane(_:))),
            item("Swap Panes", #selector(BrowserWindowController.swapPanes(_:)), "u", [.command, .option]),
            item("Same Folder in Both", #selector(BrowserWindowController.sameFolderInBoth(_:)), "=", [.command, .option]),
            .separator(),
            item("Show Terminal", #selector(BrowserWindowController.toggleTerminal(_:)), "`", [.control]),
            item("Show Hidden Files", #selector(BrowserWindowController.toggleHiddenFiles(_:)), ".", [.command, .shift]),
            item("Reload", #selector(BrowserWindowController.reloadFolder(_:)), "r"),
            .separator(),
            item("Show Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))
        main.addItem(submenu("Go", [
            item("Back", #selector(BrowserWindowController.goBack(_:)), "["),
            item("Forward", #selector(BrowserWindowController.goForward(_:)), "]"),
            item("Up One Folder", #selector(BrowserWindowController.goUp(_:)), functionKey(NSUpArrowFunctionKey)),
            .separator(),
            item("Go to Path…", #selector(BrowserWindowController.editPath(_:)), "l"),
            .separator(),
            item("Home", #selector(BrowserWindowController.goHome(_:)), "h", [.command, .shift]),
            item("Desktop", #selector(BrowserWindowController.goDesktop(_:)), "d", [.command, .shift]),
            item("Documents", #selector(BrowserWindowController.goDocuments(_:)), "o", [.command, .shift]),
            item("Downloads", #selector(BrowserWindowController.goDownloads(_:)), "l", [.command, .option]),
            item("Applications", #selector(BrowserWindowController.goApplications(_:)), "a", [.command, .shift]),
        ]))
        let window = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        main.addItem(window)
        NSApp.windowsMenu = window.submenu
        return main
    }

    private static func sel(_ name: String) -> Selector { Selector((name)) }

    private static func functionKey(_ key: Int) -> String { String(Character(UnicodeScalar(UInt16(key))!)) }

    private static func item(_ title: String, _ action: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        return i
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        top.submenu = menu
        return top
    }
}
