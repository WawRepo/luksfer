import AppKit
import LuksferCore

extension Notification.Name {
    /// The set of cut items changed (lists draw them dimmed).
    static let luksferCutChanged = Notification.Name("LuksferCutChanged")
}

/// File changes started from the UI, on top of `FileOperationEngine`: clipboard, undo and redo,
/// the name-clash dialog, and progress in the status bar. Every change is undoable or asks first.
final class FileActions {
    static let shared = FileActions()
    /// `LUKSFER_TRASH_DIR` gives test runs a sandbox "Trash" so they never touch the real one.
    let engine = FileOperationEngine(trasher: ProcessInfo.processInfo.environment["LUKSFER_TRASH_DIR"]
        .map { FolderTrasher(folder: URL(fileURLWithPath: $0, isDirectory: true)) as Trasher } ?? SystemTrasher())
    private var undoManager: UndoManager { AppServices.shared.undoManager }
    private var running: Task<Void, Never>?
    /// File jobs and undos still running. Undo waits for them (see `isBusy`).
    private var pending = 0
    /// A file job or an undo is still running. Undo and Redo stay off until it ends, so ⌘Z never
    /// undoes an older step while a slow copy finishes.
    var isBusy: Bool { pending > 0 }
    private(set) var cutURLs: Set<URL> = []
    private var cutChangeCount = -1

    // MARK: Clipboard (standard file URLs, so Finder and other apps see normal files)

    func copy(_ urls: [URL]) {
        write(urls, cut: false)
    }

    func cut(_ urls: [URL]) {
        write(urls, cut: true)
    }

    private func write(_ urls: [URL], cut: Bool) {
        guard !urls.isEmpty else { return }
        let pb = FileClipboard.pasteboard
        pb.clearContents()
        pb.writeObjects(urls.map { $0 as NSURL })
        if cut {
            pb.addTypes([FileClipboard.cutType], owner: nil)
            pb.setString("1", forType: FileClipboard.cutType)
        }
        cutURLs = cut ? Set(urls.map(\.standardizedFileURL)) : []
        cutChangeCount = pb.changeCount
        NotificationCenter.default.post(name: .luksferCutChanged, object: nil)
    }

    /// The cut items still waiting for a paste (empty once another app changed the clipboard).
    var pendingCut: Set<URL> {
        FileClipboard.pasteboard.changeCount == cutChangeCount ? cutURLs : []
    }

    /// Pastes the clipboard's files into `folder`: a cut moves them, a copy copies them.
    /// `forceMove` is Finder's ⌥⌘V.
    func paste(into folder: URL, forceMove: Bool = false, in window: BrowserWindowController) {
        let pb = FileClipboard.pasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else {
            NSSound.beep()
            return
        }
        let isCut = pb.types?.contains(FileClipboard.cutType) == true
        let move = forceMove || isCut
        transfer(urls, into: folder, operation: move ? .move : .copy, in: window) { [weak self] in
            // After a cut is pasted, the clipboard no longer holds it (like Explorer).
            guard let self, isCut else { return }
            if FileClipboard.pasteboard.changeCount == self.cutChangeCount { FileClipboard.pasteboard.clearContents() }
            self.cutURLs = []
            NotificationCenter.default.post(name: .luksferCutChanged, object: nil)
        }
    }

    // MARK: Copy and move

    func transfer(_ urls: [URL], into folder: URL, operation: DropOperation, in window: BrowserWindowController, then: (() -> Void)? = nil) {
        let verb = operation == .move ? "Moving" : "Copying"
        let resolver = clashResolver(for: window)
        run(in: window, title: "\(verb) \(describe(urls))", select: folder) { [engine] progress in
            operation == .move
                ? try await engine.move(urls, into: folder, resolveClash: resolver, progress: progress)
                : try await engine.copy(urls, into: folder, resolveClash: resolver, progress: progress)
        } then: { then?() }
    }

    func duplicate(_ urls: [URL], in window: BrowserWindowController) {
        guard let folder = urls.first?.deletingLastPathComponent() else { return }
        run(in: window, title: "Duplicating \(describe(urls))", select: folder) { [engine] progress in
            try await engine.duplicate(urls, progress: progress)
        }
    }

    // MARK: Trash and delete

    func trash(_ urls: [URL], in window: BrowserWindowController) {
        guard !urls.isEmpty else { return }
        run(in: window, title: "Moving \(describe(urls)) to the Trash", select: nil) { [engine] _ in
            try await engine.trash(urls)
        }
    }

    /// Deletes for good, after the user confirms. This is the only change that cannot be undone.
    func deletePermanently(_ urls: [URL], in window: BrowserWindowController) {
        guard !urls.isEmpty, let w = window.window else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = urls.count == 1 ? "Delete “\(urls[0].lastPathComponent)” for good?" : "Delete \(urls.count) items for good?"
        alert.informativeText = "They do not go to the Trash. You can't undo this."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: w) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            Task { @MainActor in
                do { try await self.engine.deletePermanently(urls) } catch { window.showError(error) }
                window.panes.forEach { $0.reload() }
            }
        }
    }

    // MARK: Rename and new items

    /// Renames `url`. On an error, `onFailure` runs after the user closes the error.
    func rename(_ url: URL, to name: String, in window: BrowserWindowController, onFailure: (() -> Void)? = nil) {
        do {
            let change = try engine.rename(url, to: name)
            record(change)
            reloadPanes(in: window, showing: change.touchedFolders, select: change.createdItems)
        } catch {
            window.showError(error, then: onFailure)
        }
    }

    /// Makes a new folder or file in `folder`, then opens its name for typing (Esc keeps it).
    func create(folder: Bool, named name: String, in parent: URL, window: BrowserWindowController) {
        do {
            let change = folder ? try engine.createFolder(in: parent, named: name) : try engine.createFile(in: parent, named: name)
            record(change)
            guard let item = change.createdItems.first else { return }
            let pane = window.activePane.folder.standardizedFileURL == parent.standardizedFileURL ? window.activePane : nil
            if let pane {
                pane.list.reload(select: [item]) { pane.list.beginRename(item) }
            } else {
                reloadPanes(in: window, showing: [parent], select: [item])
            }
        } catch {
            window.showError(error)
        }
    }

    // MARK: Compress

    /// Zips the items next to them with `ditto` (like Finder's Compress). Undo moves the zip to the Trash.
    func compress(_ urls: [URL], in window: BrowserWindowController) {
        guard let folder = urls.first?.deletingLastPathComponent() else { return }
        let base = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Archive"
        let name = FileOperationEngine.uniqueName("\(base).zip", in: folder, style: .numbered)
        let zip = folder.appendingPathComponent(name)
        window.statusBar.showProgress("Compressing \(describe(urls))", fraction: nil)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let p = Process()
            if urls.count == 1 {
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, zip.path]
            } else {
                // Several items: zip them by name from their folder (-y keeps links as links).
                p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                p.currentDirectoryURL = folder
                p.arguments = ["-r", "-y", "-q", zip.path] + urls.map(\.lastPathComponent)
            }
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async {
                window.statusBar.hideProgress()
                guard let self, p.terminationStatus == 0 else { NSSound.beep(); return }
                self.registerStep("Compress") { target in
                    Task { @MainActor in
                        do { _ = try await target.engine.trash([zip]) } catch { window.showError(error) }
                    }
                }
                self.reloadPanes(in: window, showing: [folder], select: [zip])
            }
        }
    }

    // MARK: Running, progress, undo

    func cancelCurrent() { running?.cancel() }

    private func run(in window: BrowserWindowController, title: String, select folder: URL?,
                     _ work: @escaping (@escaping FileOperationEngine.ProgressHandler) async throws -> FileChange,
                     then: (() -> Void)? = nil) {
        let status = window.statusBar
        let started = Date()
        pending += 1
        // Short operations never flash the progress bar.
        let show = DispatchWorkItem { status.showProgress(title, fraction: nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: show)
        let progress: FileOperationEngine.ProgressHandler = { p in
            DispatchQueue.main.async {
                guard Date().timeIntervalSince(started) > 0.4 else { return }
                let detail = p.totalBytes > 0 ? "\(Formatters.size(p.completedBytes)) of \(Formatters.size(p.totalBytes))" : "\(p.completedItems) of \(p.totalItems)"
                status.showProgress("\(title) — \(detail)", fraction: p.fraction)
            }
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let change = try await work(progress)
                self.record(change)
                self.reloadPanes(in: window, showing: change.touchedFolders, select: change.createdItems)
                then?()
            } catch let error as FileOperationError {
                if let partial = error.partialChange { self.record(partial) }
                window.panes.forEach { $0.reload() }
                if case .cancelled = error {} else { window.showError(error) }
            } catch {
                window.showError(error)
            }
            show.cancel()
            status.hideProgress()
            self.running = nil
            self.pending -= 1
        }
        running = task
    }

    /// Registers a change on the shared undo stack. Undo and redo both apply the inverse change,
    /// which the engine returns, so the redo is registered while the undo runs.
    private func record(_ change: FileChange) {
        guard !change.isEmpty else { return }
        registerStep(change.actionName) { target in target.reverse(change) }
    }

    /// Registers one undo step as its own closed group. A job that ends in a task (not during an
    /// event) would leave AppKit's automatic group open until the next event, so the next action
    /// joined it and one ⌘Z undid both.
    private func registerStep(_ name: String, _ handler: @escaping (FileActions) -> Void) {
        let manager = undoManager
        guard manager.groupingLevel == 0, !manager.isUndoing, !manager.isRedoing else {
            manager.registerUndo(withTarget: self, handler: handler)
            manager.setActionName(name)
            return
        }
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self, handler: handler)
        manager.setActionName(name)
        manager.endUndoGrouping()
        manager.groupsByEvent = true
    }

    private func reverse(_ change: FileChange) {
        let box = ChangeBox()
        // Registered now, while the undo manager is undoing (or redoing), so it lands on the
        // opposite stack. It runs once the inverse is known.
        undoManager.registerUndo(withTarget: self) { target in
            if let next = box.change { target.reverse(next) } else { NSSound.beep() }
        }
        undoManager.setActionName(change.actionName)
        let window = NSApp.keyWindow?.windowController as? BrowserWindowController
        pending += 1
        Task { @MainActor in
            defer { self.pending -= 1 }
            do {
                box.change = try await engine.undo(change)
            } catch let error as FileOperationError {
                box.change = error.partialChange
                window?.showError(error)
            } catch {
                window?.showError(error)
            }
            for c in NSApp.windows.compactMap({ $0.windowController as? BrowserWindowController }) {
                self.reloadPanes(in: c, showing: change.touchedFolders, select: box.change?.createdItems ?? [])
            }
        }
    }

    private func reloadPanes(in window: BrowserWindowController, showing folders: Set<URL>, select: [URL]) {
        let paths = Set(folders.map { $0.standardizedFileURL.path })
        for pane in window.panes {
            let shown = paths.contains(pane.folder.standardizedFileURL.path)
            let picks = select.filter { $0.deletingLastPathComponent().standardizedFileURL.path == pane.folder.standardizedFileURL.path }
            if shown || !picks.isEmpty { pane.list.reload(select: picks.isEmpty ? nil : picks) }
        }
    }

    private func clashResolver(for window: BrowserWindowController) -> FileOperationEngine.ClashResolver {
        { [weak window] clash in
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    ClashDialog.ask(clash, window: window?.window) { continuation.resume(returning: $0) }
                }
            }
        }
    }

    private func describe(_ urls: [URL]) -> String {
        urls.count == 1 ? "“\(urls[0].lastPathComponent)”" : "\(urls.count) items"
    }
}

/// Holds the inverse of an undone change until the engine returns it.
private final class ChangeBox: @unchecked Sendable {
    var change: FileChange?
}
