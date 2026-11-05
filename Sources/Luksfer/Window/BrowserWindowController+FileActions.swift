import AppKit
import LuksferCore

// File actions from the menus, the toolbar, keys and context menus (PRD §6.5, §6.6).
extension BrowserWindowController {
    private var selection: [URL] { activePane.list.selectedURLs }

    @objc func cut(_ sender: Any?) {
        let urls = selection
        guard !urls.isEmpty else { return }
        FileActions.shared.cut(urls)
        statusBar.showMessage("Cut \(FileActions.describe(urls)). Paste with ⌘V to move \(urls.count == 1 ? "it" : "them").")
    }

    @objc func copy(_ sender: Any?) {
        let urls = selection
        guard !urls.isEmpty else { return }
        FileActions.shared.copy(urls)
        statusBar.showMessage("Copied \(FileActions.describe(urls)). Paste with ⌘V.")
    }
    @objc func paste(_ sender: Any?) { FileActions.shared.paste(into: activePane.folder, in: self) }
    @objc func pasteMove(_ sender: Any?) { FileActions.shared.paste(into: activePane.folder, forceMove: true, in: self) }

    /// Context menu "Paste into" on a folder: the folder is the menu item's represented object.
    @objc func pasteInto(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? URL else { return }
        FileActions.shared.paste(into: folder, in: self)
    }

    @objc func renameSelection(_ sender: Any?) {
        guard let item = activePane.list.selectedItems.first else { return }
        activePane.list.beginRename(item.url)
    }

    @objc func moveToTrash(_ sender: Any?) { FileActions.shared.trash(selection, in: self) }
    @objc func deleteImmediately(_ sender: Any?) { FileActions.shared.deletePermanently(selection, in: self) }
    @objc func duplicateItems(_ sender: Any?) { FileActions.shared.duplicate(selection, in: self) }
    @objc func compressItems(_ sender: Any?) { FileActions.shared.compress(selection, in: self) }
    @objc func extractItems(_ sender: Any?) { FileActions.shared.extract(selection, in: self) }

    @objc func getInfo(_ sender: Any?) {
        let items = activePane.list.selectedItems
        if items.isEmpty, let item = DirectoryReader.item(at: activePane.folder) {
            InfoPanel.show(for: item)
        } else {
            items.prefix(5).forEach(InfoPanel.show)
        }
    }

    // New items go in the folder from the context menu (inside or next to an item), else in the
    // pane's folder.
    @objc func newFolder(_ sender: Any?) { create(folder: true, name: "New folder", sender) }
    @objc func newTextFile(_ sender: Any?) { create(folder: false, name: "New text file.txt", sender) }
    @objc func newMarkdownFile(_ sender: Any?) { create(folder: false, name: "New Markdown file.md", sender) }

    private func create(folder: Bool, name: String, _ sender: Any?) {
        let parent = (sender as? NSMenuItem)?.representedObject as? URL ?? activePane.folder
        FileActions.shared.create(folder: folder, named: name, in: parent, window: self)
    }

    @objc func openWith(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(selection, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Sort by: tags 0… are SortKey cases; 100 = ascending, 101 = descending.
    @objc func sortBy(_ sender: NSMenuItem) {
        var order = activePane.list.sortOrder
        if sender.tag == 100 { order.ascending = true }
        else if sender.tag == 101 { order.ascending = false }
        else if sender.tag < SortKey.allCases.count { order.key = SortKey.allCases[sender.tag] }
        activePane.list.sortOrder = order
    }
}
