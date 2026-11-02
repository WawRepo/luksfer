import AppKit
import LuksferCore
import Quartz

/// An end-to-end check of the file actions in the running app, for test runs only.
/// LUKSFER_SELFTEST=1 with LUKSFER_OPEN=<empty sandbox folder> and LUKSFER_TRASH_DIR=<sandbox trash>:
/// creates, copies, renames, trashes, undoes and redoes, prints PASS/FAIL lines, then quits.
@MainActor
enum SelfTest {
    static func scheduleIfAsked() {
        if ProcessInfo.processInfo.environment["LUKSFER_SELFTEST"] == "restore" {
            Task { await restore() }
            return
        }
        if ProcessInfo.processInfo.environment["LUKSFER_SELFTEST"] == "opened" {
            Task { await opened() }
            return
        }
        guard ProcessInfo.processInfo.environment["LUKSFER_SELFTEST"] == "1",
              ProcessInfo.processInfo.environment["LUKSFER_TRASH_DIR"] != nil,
              let folder = DevHooks.openFolder else { return }
        Task { await run(in: folder) }
    }

    private static var failures = 0

    /// Any self-test mode. The self-test never takes ⌥⌘Space from the user.
    nonisolated static var isRunning: Bool { ProcessInfo.processInfo.environment["LUKSFER_SELFTEST"] != nil }

    private static func check(_ name: String, _ ok: Bool) {
        if !ok { failures += 1 }
        FileHandle.standardError.write(Data("selftest: \(ok ? "PASS" : "FAIL") \(name)\n".utf8))
    }

    private static func names(_ folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    private static func wait(_ seconds: Double = 0.6) async { try? await Task.sleep(for: .seconds(seconds)) }

    /// Waits until file jobs and undos have finished (up to 15 s), then lets the lists reload.
    private static func settle() async {
        _ = await waitFor(15) { !FileActions.shared.isBusy }
        await wait(0.4)
    }

    /// Prints the result and quits, also when a sheet is still open. Exit code 1 on a failure.
    private static func finish() {
        FileHandle.standardError.write(Data("selftest: \(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")\n".utf8))
        if failures > 0 { exit(1) }
        for w in NSApp.windows { if let sheet = w.attachedSheet { w.endSheet(sheet) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
        NSApp.terminate(nil)   // saves the window state, for LUKSFER_SELFTEST=restore
    }

    /// Sends a key press to the view, as if typed.
    private static func key(_ code: Int, _ flags: NSEvent.ModifierFlags = [], to view: NSView) {
        let chars = String(Character(UnicodeScalar(UInt32(code))!))
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                           windowNumber: view.window?.windowNumber ?? 0, context: nil, characters: chars,
                                           charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0) else { return }
        view.keyDown(with: event)
    }

    /// Presses an extra mouse button (3 is back, 4 is forward) through the app's event dispatch.
    /// A made-up event gets a wrong spot, so the active pane takes it.
    private static func mouseButton(_ number: Int, in w: BrowserWindowController) {
        guard let window = w.window,
              let cg = NSEvent.mouseEvent(with: .otherMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)?.cgEvent
        else { return }
        cg.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
        if let event = NSEvent(cgEvent: cg) { NSApp.sendEvent(event) }
    }

    /// Finds a button by title in a view tree.
    private static func button(_ title: String, in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let b = view as? NSButton, b.title == title { return b }
        for sub in view.subviews { if let b = button(title, in: sub) { return b } }
        return nil
    }

    private static func sheetText(_ view: NSView?) -> String {
        guard let view else { return "" }
        let own = (view as? NSButton)?.title ?? (view as? NSTextField)?.stringValue ?? ""
        return ([own] + view.subviews.map(sheetText)).filter { !$0.isEmpty }.joined(separator: " | ")
    }

    /// Waits for a sheet on the window and clicks its button. False when no sheet came.
    private static func answer(_ title: String, on window: NSWindow?) async -> Bool {
        for _ in 0..<100 {
            if let sheet = window?.attachedSheet, let b = button(title, in: sheet.contentView) {
                b.performClick(nil)
                return true
            }
            await wait(0.1)
        }
        let open = window?.attachedSheet.map { sheetText($0.contentView) } ?? "no sheet"
        FileHandle.standardError.write(Data("selftest: no “\(title)” button; open: \(open)\n".utf8))
        return false
    }

    /// The name-clash question and the "delete for good" question (milestone 3).
    private static func questions(in folder: URL, window w: BrowserWindowController) async {
        let inner = folder.appendingPathComponent("New folder")
        let trash = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LUKSFER_TRASH_DIR"]!)
        let trashed = names(trash).count
        FileActions.shared.transfer([folder.appendingPathComponent("notes.md")], into: inner, operation: .copy, in: w)
        _ = await waitFor(10) { w.window?.attachedSheet != nil }
        let text = w.window?.attachedSheet.map { sheetText($0.contentView) } ?? ""
        let stop = button("Stop", in: w.window?.attachedSheet?.contentView)
        let forAll = button("Do this for all", in: w.window?.attachedSheet?.contentView)
        check("the clash question shows both sizes and dates", text.contains("New: ") && text.contains("Existing: ") && text.components(separatedBy: "modified").count == 3)
        check("the clash question has Stop on Esc", stop?.keyEquivalent == "\u{1b}")
        check("one clash has no “Do this for all”", forAll == nil || forAll?.isHidden == true || forAll?.superview == nil)
        check("a name clash asks first", await answer("Replace", on: w.window))
        await settle()
        check("Replace puts the old file in the Trash", names(trash).count == trashed + 1 && names(inner).contains("notes.md"))

        let before = names(inner)
        FileActions.shared.transfer([folder.appendingPathComponent("notes.md")], into: inner, operation: .copy, in: w)
        check("Stop ends the copy", await answer("Stop", on: w.window))
        await settle()
        check("Stop changes nothing and shows no error", names(inner) == before && w.window?.attachedSheet == nil)

        FileActions.shared.transfer([folder.appendingPathComponent("notes.md")], into: inner, operation: .copy, in: w)
        check("the clash question comes again", await answer("Keep Both", on: w.window))
        await settle()
        check("Keep Both keeps both", names(inner).count == 2)

        let file = folder.appendingPathComponent("New text file.txt")
        FileActions.shared.deletePermanently([file], in: w)
        check("Delete Immediately asks first", await answer("Cancel", on: w.window))
        await wait()
        check("Cancel keeps the file", names(folder).contains("New text file.txt"))
    }

    /// Milestone 2 and 4: keys, Quick Look, search, sort, hidden files, Favorites, pane switching.
    private static func navigation(in folder: URL, window w: BrowserWindowController) async {
        let inner = folder.appendingPathComponent("New folder")
        w.setActive(0)
        let pane = w.activePane
        pane.navigate(to: folder)
        await wait()
        let table = pane.list.tableView
        pane.list.focus()

        // The folder menu is short: the four New items sit in a New submenu, and shortcuts show.
        if let item = pane.list.items.first(where: { $0.name == "New folder" }) {
            let menu = ContextMenus.menu(for: [item], in: pane, window: w)
            let top = menu.items.filter { !$0.isSeparatorItem }
            let new = top.first { $0.title == "New" }?.submenu?.items.map(\.title) ?? []
            check("the folder menu is short, with a New submenu", top.count <= 15
                  && ["New Folder Inside", "New Text File Inside", "New Folder Next to It", "New Text File Next to It"].allSatisfy(new.contains))
            check("the menu shows the key shortcuts", top.first { $0.title == "Copy" }?.keyEquivalent == "c"
                  && top.first { $0.title == "Move to Trash" }?.keyEquivalent == "\u{8}"
                  && top.first { $0.title == "Rename" }?.keyEquivalent == String(Character(UnicodeScalar(UInt32(NSF2FunctionKey))!)))
        } else {
            check("New folder is listed", false)
        }

        pane.list.select([inner], scroll: false)
        key(NSCarriageReturnCharacter, to: table)
        await wait()
        check("Enter opens a folder", pane.folder.standardizedFileURL == inner.standardizedFileURL)
        key(NSDeleteCharacter, to: table)
        await wait()
        check("Backspace goes back", pane.folder.standardizedFileURL == folder.standardizedFileURL)
        check("going back selects the folder you came from", pane.list.selectedItems.map(\.name) == ["New folder"])
        key(NSDownArrowFunctionKey, .command, to: table)
        await wait()
        check("⌘↓ opens a folder", pane.folder.standardizedFileURL == inner.standardizedFileURL)
        key(NSUpArrowFunctionKey, .command, to: table)
        await wait()
        check("⌘↑ goes up", pane.folder.standardizedFileURL == folder.standardizedFileURL)
        mouseButton(3, in: w)
        await wait()
        check("the mouse back button goes back", pane.folder.standardizedFileURL == inner.standardizedFileURL)
        mouseButton(4, in: w)
        await wait()
        check("the mouse forward button goes forward", pane.folder.standardizedFileURL == folder.standardizedFileURL)

        // A slow folder: the old rows go, so nothing acts on the old folder while it loads.
        pane.list.select([folder.appendingPathComponent("notes.md")], scroll: false)
        FileListViewController.listDelayForTests = 1.5
        pane.navigate(to: inner)
        await wait(0.6)
        let trashItem = NSMenuItem(title: "", action: #selector(BrowserWindowController.moveToTrash(_:)), keyEquivalent: "")
        check("old rows go while a slow folder loads", pane.list.isLoading && pane.list.items.isEmpty && !w.validateMenuItem(trashItem))
        FileListViewController.listDelayForTests = 0
        check("the slow folder shows once it has loaded", await waitFor(5) { !pane.list.isLoading } && !pane.list.items.isEmpty)
        pane.goBack()
        await wait()
        pane.list.focus()

        pane.list.select([folder.appendingPathComponent("notes.md")], scroll: false)
        key(0x20, to: table)
        await wait(1.0)
        check("Space opens Quick Look", QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible)
        pane.list.toggleQuickLook()
        await wait()
        // Without a key window (another app is in front) the panel has no controller and does not
        // close. The test must not take focus from the user, so it skips this check then.
        if NSApp.keyWindow == nil {
            FileHandle.standardError.write(Data("selftest: SKIP Quick Look closes (Luksfer is not the active app)\n".utf8))
        } else {
            check("Quick Look closes", !QLPreviewPanel.shared().isVisible)
        }
        pane.list.focus()

        pane.list.select([folder.appendingPathComponent("notes.md")], scroll: false)
        key(NSF2FunctionKey, to: table)
        await wait()
        check("F2 starts rename", pane.list.isRenaming)
        pane.list.focus()
        await wait()

        pane.list.filterQuery = "notes"
        check("search box filters the list", pane.list.items.map(\.name) == ["notes.md"])
        pane.list.filterQuery = ""

        let byName = pane.list.items.map(\.name)
        pane.list.sortOrder = FileSortOrder(key: .name, ascending: false)
        let reversed = pane.list.items.map(\.name)
        let firstFolder = pane.list.items.firstIndex(where: \.isFolder) ?? 0
        check("Z to A puts files first and folders last (like Explorer)", firstFolder > 0
              && pane.list.items[firstFolder...].allSatisfy(\.isFolder) && reversed != byName)
        pane.list.sortOrder = FileSortOrder()

        FileManager.default.createFile(atPath: folder.appendingPathComponent(".secret").path, contents: nil)
        pane.reload()
        await wait()
        check("hidden files stay hidden", !pane.list.items.contains { $0.name == ".secret" })
        w.toggleHiddenFiles(nil)
        await wait()
        check("Show Hidden Files shows them", pane.list.items.contains { $0.name == ".secret" })
        w.toggleHiddenFiles(nil)
        await wait()

        AppServices.shared.pin([inner])
        check("Pin to Favorites", AppServices.shared.isFavorite(inner))
        AppServices.shared.unpin(inner)
        check("Unpin", !AppServices.shared.isFavorite(inner))

        key(NSTabCharacter, to: table)
        await wait()
        check("Tab switches to the other pane", w.activePane === w.panes[1])
        w.setActive(0)
    }

    /// Milestone 4: drops between panes, onto a folder row, onto the sidebar, and ⌥ copy.
    private static func drops(in folder: URL, window w: BrowserWindowController) async {
        let inner = folder.appendingPathComponent("New folder")
        let file = folder.appendingPathComponent("New text file.txt")
        let undo = AppServices.shared.undoManager
        w.setTwoPanes(true, focus: false)
        w.setActive(0)
        w.panes[0].navigate(to: folder)
        w.panes[1].navigate(to: inner)
        await wait()
        let left = w.panes[0].list, right = w.panes[1].list

        check("VoiceOver names the two panes and their lists",
              w.panes[0].view.accessibilityLabel() == "Left pane" && w.panes[1].view.accessibilityLabel() == "Right pane"
              && left.tableView.accessibilityLabel() == "Files, left pane" && right.tableView.accessibilityLabel() == "Files, right pane")
        check("only the active pane is marked", w.panes[0].showsAsActive && !w.panes[1].showsAsActive)
        w.paneDidBecomeActive(w.panes[1])
        await wait(0.3)
        check("the mark follows the active pane", w.panes[1].showsAsActive && !w.panes[0].showsAsActive)
        DevHooks.snapshot(to: folder.deletingLastPathComponent().appendingPathComponent("active-pane.png"))
        w.setActive(0)

        // The mouse back button works on the pane under the pointer.
        w.panes[1].navigate(to: folder)
        w.panes[1].navigate(to: inner)
        await wait()
        let rightMiddle = w.panes[1].view.convert(NSPoint(x: w.panes[1].view.bounds.midX, y: w.panes[1].view.bounds.midY), to: nil)
        _ = w.navigate(mouseButton: 3, at: rightMiddle)
        await wait()
        check("the mouse back button works on the pane under the pointer",
              w.activePane === w.panes[1] && w.panes[1].folder.standardizedFileURL == folder.standardizedFileURL
              && w.panes[0].folder.standardizedFileURL == folder.standardizedFileURL)
        _ = w.navigate(mouseButton: 4, at: rightMiddle)
        await wait()
        check("the mouse forward button comes back", w.panes[1].folder.standardizedFileURL == inner.standardizedFileURL)
        w.setActive(0)

        let drag = SelfTestDrag([file])
        check("drop into the other pane is allowed", right.tableView(right.tableView, validateDrop: drag, proposedRow: -1, proposedDropOperation: .above) == .move)
        check("drop into its own folder does nothing", left.tableView(left.tableView, validateDrop: drag, proposedRow: -1, proposedDropOperation: .above) == [])
        let folderDrag = SelfTestDrag([inner])
        let innerRow = left.items.firstIndex { $0.name == "New folder" } ?? -1
        check("drop of a folder into itself is refused", left.tableView(left.tableView, validateDrop: folderDrag, proposedRow: innerRow, proposedDropOperation: .on) == [])

        _ = right.tableView(right.tableView, acceptDrop: drag, row: -1, dropOperation: .above)
        await settle()
        check("drag to the other pane moves (same disk)", names(inner).contains(file.lastPathComponent) && !names(folder).contains(file.lastPathComponent))
        check("both panes show the move", right.items.contains { $0.name == file.lastPathComponent } && !left.items.contains { $0.name == file.lastPathComponent })
        undo.undo()
        await settle()
        check("undo the drag", names(folder).contains(file.lastPathComponent) && !names(inner).contains(file.lastPathComponent))

        _ = right.tableView(right.tableView, acceptDrop: SelfTestDrag([file], mask: .copy), row: -1, dropOperation: .above)
        await settle()
        check("⌥ drag copies", names(inner).contains(file.lastPathComponent) && names(folder).contains(file.lastPathComponent))
        undo.undo()
        await settle()

        let row = left.items.firstIndex { $0.name == "New folder" } ?? -1
        _ = left.tableView(left.tableView, acceptDrop: SelfTestDrag([file]), row: row, dropOperation: .on)
        await settle()
        check("drop onto a folder row moves into it", names(inner).contains(file.lastPathComponent) && !names(folder).contains(file.lastPathComponent))
        undo.undo()
        await settle()

        let sidebar = w.sidebar
        guard let favorites = sidebar.groups.first(where: { $0.section == .favorites }) else { check("sidebar has Favorites", false); return }
        _ = sidebar.outlineView(sidebar.outline, acceptDrop: SelfTestDrag([inner]), item: favorites, childIndex: 0)
        await wait()
        check("drop a folder on Favorites pins it", AppServices.shared.isFavorite(inner))
        let node = sidebar.groups.first(where: { $0.section == .favorites })?.children.first { $0.url?.standardizedFileURL == inner.standardizedFileURL }
        if let node {
            _ = sidebar.outlineView(sidebar.outline, acceptDrop: SelfTestDrag([file]), item: node, childIndex: NSOutlineViewDropOnItemIndex)
            await settle()
            check("drop onto a Favorite moves into it", names(inner).contains(file.lastPathComponent) && !names(folder).contains(file.lastPathComponent))
            undo.undo()
            await settle()
        } else {
            check("pinned folder shows in the sidebar", false)
        }
        AppServices.shared.unpin(inner)
    }

    /// Waits until `condition` is true, up to `seconds`.
    private static func waitFor(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        for _ in 0..<Int(seconds * 10) {
            if condition() { return true }
            await wait(0.1)
        }
        return condition()
    }

    /// Milestone 5: the panel starts in the pane's folder, and Follow works both ways.
    /// The shell runs the user's own zsh config; Luksfer's typed cd lines stay out of the history.
    private static func terminal(in folder: URL, window w: BrowserWindowController) async {
        let inner = folder.appendingPathComponent("New folder")
        func same(_ a: URL?, _ b: URL) -> Bool { a?.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path }
        w.setTwoPanes(false)
        check("one pane shows no active mark", !w.activePane.showsAsActive)
        check("one pane's list is just “Files” for VoiceOver", w.activePane.list.tableView.accessibilityLabel() == "Files"
              && !w.activePane.view.isAccessibilityElement())
        w.activePane.navigate(to: folder)
        await wait()
        w.openTerminal(at: folder, focus: false)
        guard let t = w.terminal else { check("terminal opens", false); return }
        check("terminal starts in the pane's folder", await waitFor(15) { same(t.currentFolder, folder) && t.isAtIdlePrompt })
        if !AppServices.shared.settings.terminalFollow { t.followEnabled = true }
        w.activePane.navigate(to: inner)
        check("Follow: opening a folder moves the shell", await waitFor(10) { same(t.currentFolder, inner) && t.isAtIdlePrompt })
        check("Follow leaves no cd line in the terminal", !t.screenText.contains("cd --") && !t.screenText.isEmpty)
        t.type(" builtin cd -- \(ShellQuoting.singleQuoted(folder.path))\r")
        check("Follow: cd in the shell moves the pane", await waitFor(10) { same(w.activePane.folder, folder) })
        await printedClipboardCodes(in: folder, terminal: t)
        t.focusTerminal()
        await wait()
        w.activePane.list.select([folder.appendingPathComponent("notes.md")], scroll: false)
        let trash = NSMenuItem(title: "", action: #selector(BrowserWindowController.moveToTrash(_:)), keyEquivalent: "")
        check("file actions are off while the terminal has focus", w.terminalHasFocus && !w.validateMenuItem(trash))
        check("⌘Z in the terminal cannot undo a file action", w.window?.undoManager !== AppServices.shared.undoManager)
        await wait(1.5)
        if let window = w.window { DevHooks.grab(window, to: folder.deletingLastPathComponent().appendingPathComponent("terminal.png")) }
        w.toggleTerminal(nil)
        check("⌃` hides the terminal", !w.terminalOpen)
        w.paneOpenTerminal(w.activePane)
        check("“term” in the path bar opens the terminal", w.terminalOpen)
        check("a terminal app to open is found", TerminalAppLauncher.applicationURL(for: .terminal) != nil)
        w.closeTerminal()
        // Leave two panes open for the LUKSFER_SELFTEST=restore run.
        w.setTwoPanes(true, focus: false)
        w.panes[1].navigate(to: inner)
        await wait()
    }

    /// OSC 52: text printed in the terminal asks to set the clipboard, then asks to read it. The clipboard
    /// stays as it is and the program gets no answer. (The typed line starts with " builtin cd -- " to stay out of history.)
    private static func printedClipboardCodes(in folder: URL, terminal t: TerminalPanelController) async {
        let clipboard = NSPasteboard.general
        let before = clipboard.changeCount, saved = clipboard.string(forType: .string)
        let answer = folder.deletingLastPathComponent().appendingPathComponent("clipboard-answer.txt")
        t.type(#" builtin cd -- .; printf '\e]52;c;bHVrc2Zlci1zZWxmdGVzdA==\a\e]52;c;?\a'; read -t 2 -k 1 r; print -r -- "${#r}" > "#
               + ShellQuoting.singleQuoted(answer.path) + "\r")
        let done = await waitFor(10) { ((try? String(contentsOf: answer, encoding: .utf8)) ?? "").hasSuffix("\n") }
        await wait()
        check("printed OSC 52 cannot change the clipboard", done && clipboard.changeCount == before)
        check("printed OSC 52 cannot read the clipboard", done && (try? String(contentsOf: answer, encoding: .utf8)) == "0\n")
        if clipboard.changeCount != before, let saved {   // only after a failure
            clipboard.clearContents()
            clipboard.setString(saved, forType: .string)
        }
        _ = await waitFor(5) { t.isAtIdlePrompt }
    }

    /// ⌘N opens a second window.
    /// Network drives: the dialog, the Keychain and the sidebar. No server runs in the
    /// test, so the connection fails on purpose. LUKSFER_KEYCHAIN keeps every password in the sandbox.
    private static func networkDrives(window w: BrowserWindowController) async {
        guard ProcessInfo.processInfo.environment["LUKSFER_KEYCHAIN"] != nil else {
            FileHandle.standardError.write(Data("selftest: SKIP network drives (no LUKSFER_KEYCHAIN sandbox keychain)\n".utf8))
            return
        }
        let passwords = NetworkDrives.shared.passwords
        let secret = "fake-secret-1234"
        func networkRows() -> [SidebarNode] { w.sidebar.groups.first { $0.section == .network }?.children ?? [] }
        check("the sidebar has a Network section", w.sidebar.groups.contains { $0.section == .network })

        w.addNetworkDrive(nil)
        await wait()
        guard let dialog = NetworkDriveDialog.current else { check("Add Network Drive opens the dialog", false); return }
        check("Add waits for an address it can read", dialog.alert.buttons.first?.isEnabled == false)
        dialog.addressField.stringValue = #"\\127.0.0.1:1\Photos"#
        dialog.validate()
        check("a Windows address works", dialog.alert.buttons.first?.isEnabled == true && dialog.nameField.placeholderString == "Photos")
        dialog.userField.stringValue = "tester"
        dialog.passwordField.stringValue = secret
        dialog.alert.buttons.first?.performClick(nil)
        await wait()

        guard let drive = AppServices.shared.settings.networkDrives.first else { check("Add saves the drive", false); return }
        check("Add saves the drive without the password", drive.address == "smb://127.0.0.1:1/Photos" && drive.user == "tester" && drive.name == "Photos")
        AppServices.shared.store.saveNow()
        let saved = (try? String(contentsOf: AppServices.shared.store.fileURL, encoding: .utf8)) ?? ""
        check("settings.json has no password", saved.contains("127.0.0.1") && !saved.contains(secret))
        check("the password is in the Keychain", passwords.password(for: drive.id) == secret)
        check("the sidebar shows the drive", networkRows().contains { $0.drive?.id == drive.id && $0.url == nil })
        let failed = await waitFor(60) { sheetText(w.window?.attachedSheet?.contentView).contains("could not connect to “Photos”") }
        check("a server that does not answer gives a clear error, and the window keeps working", failed)
        _ = await answer("OK", on: w.window)
        await wait()

        w.editNetworkDrive(drive)
        await wait()
        if let edit = NetworkDriveDialog.current {
            check("Edit never shows the saved password", edit.passwordField.stringValue.isEmpty
                  && edit.passwordField.placeholderString?.contains("Keychain") == true && edit.userField.stringValue == "tester")
            edit.passwordField.stringValue = "fake-secret-5678"
            edit.alert.buttons.first?.performClick(nil)
            await wait()
            check("a typed password replaces the saved one", passwords.password(for: drive.id) == "fake-secret-5678")
        } else {
            check("Edit opens the dialog", false)
        }

        w.editNetworkDrive(drive)
        await wait()
        NetworkDriveDialog.current?.rememberBox.state = .off
        NetworkDriveDialog.current?.alert.buttons.first?.performClick(nil)
        await wait()
        check("Remember off deletes the saved password", !passwords.hasPassword(for: drive.id))
        w.connect(drive)
        await wait()
        check("without a saved password, Connect asks for it", sheetText(w.window?.attachedSheet?.contentView).contains("Enter the password of “tester”"))
        _ = await answer("Cancel", on: w.window)
        await wait()

        try? passwords.setPassword("fake-secret-9", for: drive.id, label: NetworkDrives.keychainLabel(for: drive))
        w.removeNetworkDrive(drive)
        check("Remove asks first", await answer("Remove", on: w.window))
        await wait()
        check("Remove takes the drive and its password away", AppServices.shared.settings.networkDrives.isEmpty
              && !passwords.hasPassword(for: drive.id) && !networkRows().contains { $0.drive != nil })
    }

    /// Compress with names that look like zip options: they stay file names, and no command runs.
    private static func compressOddNames(in folder: URL, window w: BrowserWindowController) async {
        let box = folder.appendingPathComponent("odd names")
        try? FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        let items = ["-T", "-TTtouch marker", "notes.txt"].map { box.appendingPathComponent($0) }
        items.forEach { FileManager.default.createFile(atPath: $0.path, contents: Data("text".utf8)) }
        FileActions.shared.compress(items, in: w)
        let made = await waitFor(10) { names(box).contains("Archive.zip") }
        await settle()
        check("Compress keeps names that look like zip options as file names, and runs nothing",
              made && !names(box).contains("marker"))
    }

    private static func newWindow() async {
        let before = NSApp.windows.filter { $0.windowController is BrowserWindowController }.count
        (NSApp.delegate as? AppDelegate)?.newWindow(nil)
        await wait()
        let after = NSApp.windows.filter { $0.windowController is BrowserWindowController && $0.isVisible }
        check("⌘N opens a new window", after.count == before + 1)
        check("the new window does not cover the other one exactly",
              Set(after.map { NSStringFromPoint(NSPoint(x: $0.frame.minX, y: $0.frame.maxY)) }).count == after.count)
        after.last?.close()
        await wait()
    }

    /// A minimized window comes back when Luksfer comes to the front or is opened again, but a
    /// shortcut that opens a folder gets a new window.
    private static func comeBack(in folder: URL, window w: BrowserWindowController) async {
        guard let window = w.window else { return }
        func browserWindows() -> Int { NSApp.windows.filter { $0.windowController is BrowserWindowController }.count }
        let before = browserWindows()
        // True when the window really went to the Dock and then came back, with no extra window.
        func minimizeThenComeBack(_ bringBack: () -> Void) async -> Bool {
            window.miniaturize(nil)
            guard await waitFor(5, { window.isMiniaturized }) else { return false }
            bringBack()
            return await waitFor(5) { !window.isMiniaturized && window.isVisible } && browserWindows() == before
        }
        check("a minimized window comes back when Luksfer comes to the front", await minimizeThenComeBack {
            (NSApp.delegate as? AppDelegate)?.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        })
        check("a minimized window comes back when Luksfer is opened again", await minimizeThenComeBack {
            // The same Apple event the Dock and `open -a` send to a running app.
            let reopen = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
                                                targetDescriptor: .currentProcess(), returnID: AEReturnID(kAutoGenerateReturnID),
                                                transactionID: AETransactionID(kAnyTransactionID))
            _ = try? reopen.sendEvent(options: [.noReply], timeout: 2)
        })

        // The shortcut: Luksfer becomes active, then gets the same open request as `open -a Luksfer <folder>`.
        let target = folder.appendingPathComponent("New folder")
        window.miniaturize(nil)
        let down = await waitFor(5) { window.isMiniaturized }
        (NSApp.delegate as? AppDelegate)?.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        let open = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments),
                                          targetDescriptor: .currentProcess(), returnID: AEReturnID(kAutoGenerateReturnID),
                                          transactionID: AETransactionID(kAnyTransactionID))
        let files = NSAppleEventDescriptor.list()
        files.insert(NSAppleEventDescriptor(fileURL: target), at: 0)
        open.setParam(files, forKeyword: AEKeyword(keyDirectObject))
        _ = try? open.sendEvent(options: [.noReply], timeout: 2)
        await wait(1.0)
        let opened = NSApp.windows.compactMap { $0.windowController as? BrowserWindowController }
            .filter { $0 !== w && $0.window?.isVisible == true }
        check("the shortcut opens a new single-pane window at its folder and leaves the minimized one",
              down && window.isMiniaturized && opened.count == 1 && !opened[0].twoPanes
              && opened[0].activePane.folder.standardizedFileURL.path == target.standardizedFileURL.path)
        window.deminiaturize(nil)
        _ = await waitFor(5) { !window.isMiniaturized && window.isVisible }
        opened.forEach { $0.window?.close() }
        window.makeKeyAndOrderFront(nil)
        await wait()

        // Pressed twice with the window on screen: each new window steps away from the front one.
        func topLeft(_ win: NSWindow?) -> String { win.map { NSStringFromPoint(NSPoint(x: $0.frame.minX, y: $0.frame.maxY)) } ?? "" }
        _ = try? open.sendEvent(options: [.noReply], timeout: 2)
        await wait()
        _ = try? open.sendEvent(options: [.noReply], timeout: 2)
        await wait()
        let twice = NSApp.windows.compactMap { $0.windowController as? BrowserWindowController }
            .filter { $0 !== w && $0.window?.isVisible == true }
        check("each shortcut window steps away from the window in front",
              twice.count == 2 && Set([topLeft(window)] + twice.map { topLeft($0.window) }).count == 3)
        twice.forEach { $0.window?.close() }
        window.makeKeyAndOrderFront(nil)
        await wait()
    }

    /// What ⌥⌘Space does (the self-test calls it, it never takes the real key), and what the key
    /// needs: Luksfer keeps running after the last window closes while the key is on.
    private static func hotKey(window w: BrowserWindowController) async {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        app.newWindowFromHotKey()
        await wait()
        let opened = NSApp.windows.compactMap { $0.windowController as? BrowserWindowController }
            .filter { $0 !== w && $0.window?.isVisible == true }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let expected = FileManager.default.fileExists(atPath: downloads.path) ? downloads : home
        check("⌥⌘Space opens a new single-pane window in Downloads", opened.count == 1 && !opened[0].twoPanes
              && opened[0].activePane.folder.standardizedFileURL.path == expected.standardizedFileURL.path)
        opened.forEach { $0.window?.close() }
        w.window?.makeKeyAndOrderFront(nil)
        await wait()
        check("Luksfer keeps running after the last window closes while ⌥⌘Space is on",
              !app.applicationShouldTerminateAfterLastWindowClosed(NSApp))
        AppServices.shared.update { $0.newWindowHotKey = false }
        check("with ⌥⌘Space off, Luksfer quits after the last window closes",
              app.applicationShouldTerminateAfterLastWindowClosed(NSApp))
        AppServices.shared.update { $0.newWindowHotKey = true }
    }

    /// LUKSFER_SELFTEST=opened, launched with `open -n … <sandbox>/opened` and the settings that the
    /// restore run left (one window, two panes): only the asked folder opens, in one single-pane window.
    private static func opened() async {
        await wait(1.5)
        let windows = NSApp.windows.compactMap { $0.windowController as? BrowserWindowController }
        check("a launch to open a folder opens only that window", windows.count == 1)
        if let w = windows.first {
            check("that window has one pane", !w.twoPanes)
            check("that window shows the folder", w.activePane.folder.lastPathComponent == "opened")
        }
        finish()
    }

    /// LUKSFER_SELFTEST=restore: the window from the last run comes back with two panes and its folders.
    private static func restore() async {
        await wait(1.5)
        let windows = NSApp.windows.compactMap { $0.windowController as? BrowserWindowController }
        check("one window comes back", windows.count == 1)
        if let w = windows.first {
            check("two panes come back", w.twoPanes)
            check("left folder comes back", w.panes[0].folder.lastPathComponent == "folder")
            check("right folder comes back", w.panes[1].folder.lastPathComponent == "New folder")
        }
        finish()
    }

    private static func run(in folder: URL) async {
        await wait(1.5)
        guard let w = NSApp.windows.compactMap({ $0.windowController as? BrowserWindowController }).first else { return }
        let list = w.activePane.list
        check("the file list has focus at launch", w.window?.firstResponder === list.tableView)
        let undo = AppServices.shared.undoManager
        let trash = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LUKSFER_TRASH_DIR"]!)

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

        // "New Folder Inside" opens that folder and starts the name there.
        let newFolder = folder.appendingPathComponent("New folder")
        let inside = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        inside.representedObject = newFolder
        w.newFolder(inside)
        _ = await waitFor(5) { list.isRenaming }
        check("New Folder Inside opens the folder and starts the name",
              w.activePane.folder.standardizedFileURL == newFolder.standardizedFileURL && list.isRenaming && names(newFolder) == ["New folder"])
        list.cancelRename()
        undo.undo()
        await settle()
        w.activePane.goBack()
        await wait()
        check("undo New Folder Inside", names(newFolder).isEmpty && w.activePane.folder.standardizedFileURL == folder.standardizedFileURL)

        list.select([folder.appendingPathComponent("New text file.txt")], scroll: false)
        w.copy(nil)
        check("Copy says what it did", w.statusBar.message == "Copied “New text file.txt”. Paste with ⌘V.")
        w.paste(nil)
        await settle()
        check("copy + paste in the same folder makes a copy", names(folder).contains("New text file copy.txt"))
        check("Paste says what it did", w.statusBar.message == "Copied “New text file copy.txt” to “\(folder.lastPathComponent)”")
        w.activePane.copyPath()
        check("Copy path says what it did", w.statusBar.message == "Copied the path"
              && FileClipboard.pasteboard.string(forType: .string) == list.selectedURLs.first?.path)

        FileActions.shared.rename(folder.appendingPathComponent("New text file copy.txt"), to: "notes.md", in: w)
        await settle()
        check("rename", names(folder).contains("notes.md") && !names(folder).contains("New text file copy.txt"))
        let trashedBefore = names(trash).count
        undo.undo()
        await settle()
        check("undo rename", names(folder).contains("New text file copy.txt") && !names(folder).contains("notes.md"))
        // The copy ended in a task just before the rename; one Undo must not undo it too.
        check("one Undo undoes one action", names(trash).count == trashedBefore && w.window?.attachedSheet == nil)
        undo.redo()
        await settle()
        check("redo rename", names(folder).contains("notes.md"))

        // A rename to a name that is taken shows the error, then opens the name again as typed.
        if let notes = list.items.first(where: { $0.name == "notes.md" }) {
            w.pane(w.activePane, rename: notes, to: "New text file.txt")
            check("a failed rename shows the error", await answer("OK", on: w.window))
            await wait()
            check("a failed rename keeps the typed name", list.isRenaming && list.renameText == "New text file.txt")
            list.cancelRename()
            await wait()
            check("Esc after a failed rename keeps the old name", !list.isRenaming && names(folder).contains("notes.md"))
        } else {
            check("notes.md is listed", false)
        }

        list.select([folder.appendingPathComponent("notes.md"), folder.appendingPathComponent("New folder")], scroll: false)
        w.moveToTrash(nil)
        await settle()
        check("move to Trash", !names(folder).contains("notes.md") && !names(folder).contains("New folder"))
        check("Trash says what it did, with Undo", w.statusBar.message == "Moved 2 items to the Trash")
        button("Undo", in: w.statusBar)?.performClick(nil)
        await settle()
        check("Undo in the status bar puts both back", names(folder).isSuperset(of: ["notes.md", "New folder"]))
        check("the message goes after Undo", w.statusBar.message.isEmpty)
        undo.redo()
        await settle()
        check("redo Trash", !names(folder).contains("notes.md"))
        undo.undo()
        await settle()

        // Cut + paste moves into a folder; the clipboard is cleared after.
        list.select([folder.appendingPathComponent("notes.md")], scroll: false)
        w.cut(nil)
        check("cut item is dimmed", list.dimmedURLs.contains { $0.lastPathComponent == "notes.md" })
        FileActions.shared.paste(into: folder.appendingPathComponent("New folder"), in: w)
        await settle()
        check("cut + paste moves", names(folder.appendingPathComponent("New folder")).contains("notes.md") && !names(folder).contains("notes.md"))
        undo.undo()
        await settle()
        check("undo move", names(folder).contains("notes.md"))

        w.setTwoPanes(true)
        w.otherPane.navigate(to: folder.appendingPathComponent("New folder"))
        await wait()
        FileActions.shared.transfer([folder.appendingPathComponent("notes.md")], into: folder.appendingPathComponent("New folder"), operation: .copy, in: w)
        await settle()
        check("copy to the other pane's folder", names(folder.appendingPathComponent("New folder")).contains("notes.md") && names(folder).contains("notes.md"))
        check("other pane shows the copy", w.otherPane.list.items.contains { $0.name == "notes.md" })

        await questions(in: folder, window: w)
        await navigation(in: folder, window: w)
        await drops(in: folder, window: w)
        await compressOddNames(in: folder, window: w)
        await newWindow()
        await comeBack(in: folder, window: w)
        await hotKey(window: w)
        await terminal(in: folder, window: w)
        await networkDrives(window: w)

        DevHooks.snapshot(to: folder.deletingLastPathComponent().appendingPathComponent("selftest.png"))
        finish()
    }
}
