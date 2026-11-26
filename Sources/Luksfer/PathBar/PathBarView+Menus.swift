import AppKit
import LuksferCore

/// The menus behind the › chevrons and the "…" button.
extension PathBarView {
    /// At most this many folders in a › menu; a last "…" item starts typing in that folder.
    static let folderMenuLimit = 300

    /// Opens the › menu of `crumb` under its chevron.
    func showFolderMenu(for crumb: PathCrumb, from button: PathBarButton) {
        let menu = folderMenu(for: crumb)
        withChevronOpen(button) { button.popUp(menu) }
    }

    /// The › menu: the folders inside `crumb`, in Finder order. Lists names only. They are read
    /// off the main thread: a slow network or cloud folder shows "Loading…" until they are there.
    func folderMenu(for crumb: PathCrumb) -> NSMenu {
        let menu = NSMenu(title: crumb.title)
        menu.autoenablesItems = false
        let loading = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        loading.isEnabled = false
        menu.addItem(loading)
        let read = FolderRead()
        let url = crumb.url, hidden = showsHiddenFolders, delay = Self.diskDelayForTests
        read.group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            read.folders = Subfolders.list(in: url, includeHidden: hidden)
            read.group.leave()
        }
        // A quick folder fills the menu before it opens, so "Loading…" does not flash.
        if read.group.wait(timeout: .now() + 0.15) == .success {
            fill(menu, with: read.folders, crumb: crumb)
        } else {
            // Also while the menu is open: the main queue runs during menu tracking.
            read.group.notify(queue: .main) { [weak self] in self?.fill(menu, with: read.folders, crumb: crumb) }
        }
        return menu
    }

    private func fill(_ menu: NSMenu, with folders: [URL], crumb: PathCrumb) {
        menu.removeAllItems()
        for url in folders.prefix(Self.folderMenuLimit) {
            menu.addItem(folderItem(title: url.lastPathComponent, url: url))
        }
        if folders.count > Self.folderMenuLimit {
            let more = NSMenuItem(title: "…", action: #selector(typeInFolder(_:)), keyEquivalent: "")
            more.target = self
            more.representedObject = crumb.url
            more.toolTip = "\(folders.count - Self.folderMenuLimit) more: type the name"
            menu.addItem(more)
        }
        if folders.isEmpty {
            let empty = NSMenuItem(title: "No folders inside", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
    }

    /// The "…" menu: the crumbs that did not fit, top folder first.
    func showCrumbMenu(_ crumbs: [PathCrumb], from button: PathBarButton) {
        let menu = NSMenu(title: "Path")
        menu.autoenablesItems = false
        for crumb in crumbs {
            menu.addItem(folderItem(title: crumb.title, url: crumb.url))
        }
        button.popUp(menu)
    }

    private func folderItem(title: String, url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openFolderItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
        item.image = Self.folderIcon
        return item
    }

    /// Shows a down chevron on `button` while its menu is open.
    private func withChevronOpen(_ button: PathBarButton, _ body: () -> Void) {
        let closed = button.image
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        body()
        button.image = closed
    }

    @objc private func openFolderItem(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL else { return }
        open(url)
    }

    @objc private func typeInFolder(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL else { return }
        beginEditing(text: url.path == "/" ? "/" : url.path + "/", selectAll: false)
    }
}

/// The folders of one › menu, read on a background queue. `group` says when they are there.
private final class FolderRead: @unchecked Sendable {
    let group = DispatchGroup()
    var folders: [URL] = []
}
