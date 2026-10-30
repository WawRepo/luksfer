import AppKit
import OknoCore

/// An end-to-end check of the file actions in the running app, for test runs only.
/// OKNO_SELFTEST=1 with OKNO_OPEN=<empty sandbox folder> and OKNO_TRASH_DIR=<sandbox trash>:
/// creates, copies, renames, trashes, undoes and redoes, prints PASS/FAIL lines, then quits.
@MainActor
enum SelfTest {
    static func scheduleIfAsked() {
        guard ProcessInfo.processInfo.environment["OKNO_SELFTEST"] == "1",
              ProcessInfo.processInfo.environment["OKNO_TRASH_DIR"] != nil,
              let folder = DevHooks.openFolder else { return }
        Task { await run(in: folder) }
    }

    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool) {
        if !ok { failures += 1 }
        FileHandle.standardError.write(Data("selftest: \(ok ? "PASS" : "FAIL") \(name)\n".utf8))
    }

    private static func names(_ folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    private static func wait(_ seconds: Double = 0.6) async { try? await Task.sleep(for: .seconds(seconds)) }

    private static func run(in folder: URL) async {
        await wait(1.5)
        guard let w = NSApp.windows.compactMap({ $0.windowController as? BrowserWindowController }).first else { return }
        let list = w.activePane.list
        let undo = AppServices.shared.undoManager

        w.newFolder(nil)
        await wait()
        check("new folder exists", names(folder).contains("New folder"))
        check("new folder opens its name for typing", list.isRenaming)
        w.window?.makeFirstResponder(list.tableView)   // leave the name as it is
        await wait()

        w.newTextFile(nil)
        await wait()
        w.window?.makeFirstResponder(list.tableView)
        await wait()
        check("new text file exists", names(folder).contains("New text file.txt"))

        list.select([folder.appendingPathComponent("New text file.txt")], scroll: false)
        let pasteboardBefore = NSPasteboard.general.changeCount
        w.copy(nil)
        w.paste(nil)
        await wait(1.2)
        check("copy + paste in the same folder makes a copy", names(folder).contains("New text file copy.txt"))
        _ = pasteboardBefore

        FileActions.shared.rename(folder.appendingPathComponent("New text file copy.txt"), to: "notes.md", in: w)
        await wait()
        check("rename", names(folder).contains("notes.md") && !names(folder).contains("New text file copy.txt"))
        undo.undo()
        await wait()
        check("undo rename", names(folder).contains("New text file copy.txt") && !names(folder).contains("notes.md"))
        undo.redo()
        await wait()
        check("redo rename", names(folder).contains("notes.md"))

        list.select([folder.appendingPathComponent("notes.md"), folder.appendingPathComponent("New folder")], scroll: false)
        w.moveToTrash(nil)
        await wait(1.2)
        check("move to Trash", !names(folder).contains("notes.md") && !names(folder).contains("New folder"))
        undo.undo()
        await wait(1.2)
        check("undo Trash puts both back", names(folder).isSuperset(of: ["notes.md", "New folder"]))
        undo.redo()
        await wait(1.2)
        check("redo Trash", !names(folder).contains("notes.md"))
        undo.undo()
        await wait(1.2)

        // Cut + paste moves into a folder; the clipboard is cleared after.
        list.select([folder.appendingPathComponent("notes.md")], scroll: false)
        w.cut(nil)
        check("cut item is dimmed", list.dimmedURLs.contains { $0.lastPathComponent == "notes.md" })
        FileActions.shared.paste(into: folder.appendingPathComponent("New folder"), in: w)
        await wait(1.2)
        check("cut + paste moves", names(folder.appendingPathComponent("New folder")).contains("notes.md") && !names(folder).contains("notes.md"))
        undo.undo()
        await wait(1.2)
        check("undo move", names(folder).contains("notes.md"))

        w.setTwoPanes(true)
        w.otherPane.navigate(to: folder.appendingPathComponent("New folder"))
        await wait()
        FileActions.shared.transfer([folder.appendingPathComponent("notes.md")], into: folder.appendingPathComponent("New folder"), operation: .copy, in: w)
        await wait(1.2)
        check("copy to the other pane's folder", names(folder.appendingPathComponent("New folder")).contains("notes.md") && names(folder).contains("notes.md"))
        check("other pane shows the copy", w.otherPane.list.items.contains { $0.name == "notes.md" })

        DevHooks.snapshot(to: folder.deletingLastPathComponent().appendingPathComponent("selftest.png"))
        FileHandle.standardError.write(Data("selftest: \(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")\n".utf8))
        NSApp.terminate(nil)
    }
}
