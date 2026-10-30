import Darwin
import Foundation

extension FileOperationEngine {
    /// Copies items into `folder`. Pasting into the folder an item is in makes "name copy".
    /// Name clashes go to `resolveClash`. On cancel, throws `.cancelled(partial:)`.
    public func copy(_ items: [URL], into folder: URL, resolveClash: @escaping ClashResolver,
                     progress: ProgressHandler?) async throws -> FileChange {
        try await transfer(items.map { Job(source: $0, folder: folder) }, mode: .copy, action: "Copy",
                           resolveClash: resolveClash, progress: progress)
    }

    /// Moves items into `folder`: a rename on the same volume, else copy and then remove the original.
    /// Items already in `folder` stay put. Name clashes go to `resolveClash`.
    public func move(_ items: [URL], into folder: URL, resolveClash: @escaping ClashResolver,
                     progress: ProgressHandler?) async throws -> FileChange {
        let items = Self.withoutNested(items)
        return try await transfer(items.map { Job(source: $0, folder: folder) }, mode: .move, action: "Move",
                                  resolveClash: resolveClash, progress: progress)
    }

    /// Copies each item next to itself as "name copy.ext", then "name copy 2.ext".
    public func duplicate(_ items: [URL], progress: ProgressHandler? = nil) async throws -> FileChange {
        try await transfer(items.map { Job(source: $0, folder: $0.deletingLastPathComponent()) }, mode: .copy,
                           action: "Duplicate", resolveClash: nil, progress: progress)
    }

    // MARK: The transfer loop

    enum Mode: Sendable { case copy, move }

    struct Job: Sendable {
        let source: URL
        let folder: URL
    }

    /// A job checked before anything changes.
    struct PreparedJob: Sendable {
        let source: URL
        let folder: URL
        let isFolder: Bool
        /// Bytes to copy: the whole tree for a copy or a move across volumes, 0 for a rename.
        let bytes: Int64
        let sameVolume: Bool
    }

    /// Where one item goes.
    enum Target: Sendable {
        /// Already there (a move into its own folder): nothing to do.
        case none
        /// The name is free (or a "copy" name was picked).
        case free(URL)
        /// A different item has the name.
        case clash(existing: URL, existingIsFolder: Bool)
    }

    /// Why one item stopped: cancelled or failed, with any steps that stayed done.
    struct ItemStop: Error {
        let cancelled: Bool
        let message: String
        let done: [FileChange.Step]
    }

    func transfer(_ jobs: [Job], mode: Mode, action: String, resolveClash: ClashResolver?,
                  progress: ProgressHandler?) async throws -> FileChange {
        let cancel = CancelFlag()
        return try await withTaskCancellationHandler {
            try await runTransfer(jobs, mode: mode, action: action, resolveClash: resolveClash,
                                  progress: progress, cancel: cancel)
        } onCancel: {
            cancel.cancel()
        }
    }

    private func runTransfer(_ jobs: [Job], mode: Mode, action: String, resolveClash: ClashResolver?,
                             progress: ProgressHandler?, cancel: CancelFlag) async throws -> FileChange {
        // Check every item first, so these errors come before any change.
        let prepared = try await onQueue { try self.prepare(jobs, mode: mode) }
        let tracker = ProgressTracker(totalBytes: prepared.reduce(0) { $0 + $1.bytes },
                                      totalItems: prepared.count, interval: progressInterval, handler: progress)
        var steps: [FileChange.Step] = []
        var remembered: ClashChoice?
        func cancelled() -> FileOperationError {
            .cancelled(partial: steps.isEmpty ? nil : FileChange(actionName: action, steps: steps))
        }

        for job in prepared {
            if cancel.isCancelled { throw cancelled() }
            tracker.beginItem(name: job.source.lastPathComponent, bytes: job.bytes)
            let target = try await onQueue { self.target(for: job, mode: mode) }
            var destination: URL
            var replacing: URL?
            var keepBoth = false
            switch target {
            case .none:
                tracker.finishItem()
                continue
            case .free(let url):
                destination = url
            case .clash(let existing, let existingIsFolder):
                var choice = remembered
                if choice == nil {
                    let clash = NameClash(source: job.source, existing: existing,
                                          sourceIsFolder: job.isFolder, existingIsFolder: existingIsFolder)
                    let decision = await resolveClash?(clash) ?? ClashDecision(choice: .keepBoth)
                    if decision.applyToAll { remembered = decision.choice }
                    choice = decision.choice
                }
                if cancel.isCancelled { throw cancelled() }
                destination = existing
                switch choice ?? .keepBoth {
                case .skip:
                    tracker.finishItem()
                    continue
                case .keepBoth: keepBoth = true
                case .replace: replacing = existing
                }
            }
            let finalDestination = destination, replaced = replacing, numbered = keepBoth
            do {
                steps += try await onQueue {
                    try self.perform(job, to: finalDestination, keepBoth: numbered, replacing: replaced,
                                     mode: mode, copier: TreeCopier(cancel: cancel, tracker: tracker))
                }
                tracker.finishItem()
            } catch let stop as ItemStop {
                steps += stop.done
                if stop.cancelled { throw cancelled() }
                throw Self.stopped(stop.message, action: action, steps: steps)
            }
        }
        return FileChange(actionName: action, steps: steps)
    }

    /// Checks that sources and folders exist and that no folder goes into itself; counts bytes.
    private func prepare(_ jobs: [Job], mode: Mode) throws -> [PreparedJob] {
        try jobs.map { job in
            guard let info = FileSystem.info(job.source) else {
                throw FileOperationError.sourceMissing(job.source.lastPathComponent)
            }
            guard FileSystem.folderID(job.folder) != nil else {
                throw FileOperationError.sourceMissing(job.folder.lastPathComponent)
            }
            if info.isFolder, FileSystem.isFolder(job.folder, insideOf: job.source) {
                throw FileOperationError.intoItself(job.source.lastPathComponent)
            }
            let sameVolume = mode == .move && isSameVolume(job.source.deletingLastPathComponent(), job.folder)
            let bytes = sameVolume ? 0 : FileSystem.treeBytes(job.source)
            return PreparedJob(source: job.source, folder: job.folder, isFolder: info.isFolder,
                               bytes: bytes, sameVolume: sameVolume)
        }
    }

    /// Decides where an item goes, looking at what is in the folder right now.
    private func target(for job: PreparedJob, mode: Mode) -> Target {
        let name = job.source.lastPathComponent
        let destination = job.folder.appendingPathComponent(name, isDirectory: job.isFolder)
        guard let existing = FileSystem.info(destination) else { return .free(destination) }
        let isSameItem = existing.id == FileSystem.info(job.source)?.id
            && FileSystem.folderID(job.folder) == FileSystem.folderID(job.source.deletingLastPathComponent())
        guard isSameItem else { return .clash(existing: destination, existingIsFolder: existing.isFolder) }
        switch mode {
        case .move:
            return .none
        case .copy:
            let copyName = Self.uniqueName(name, in: job.folder, style: .copy)
            return .free(job.folder.appendingPathComponent(copyName, isDirectory: job.isFolder))
        }
    }

    /// Copies or moves one item. With `replacing`, that item goes to the Trash first and comes
    /// back if the copy fails or is cancelled. Returns the steps done; throws `ItemStop`.
    private func perform(_ job: PreparedJob, to destination: URL, keepBoth: Bool, replacing: URL?,
                         mode: Mode, copier: TreeCopier) throws -> [FileChange.Step] {
        var done: [FileChange.Step] = []
        var destination = destination
        if keepBoth {
            let name = Self.uniqueName(destination.lastPathComponent, in: job.folder, style: .numbered)
            destination = job.folder.appendingPathComponent(name, isDirectory: job.isFolder)
        }
        var trashed: (original: URL, inTrash: URL)?
        if let existing = replacing {
            if FileSystem.isFolder(job.source.deletingLastPathComponent(), insideOf: existing) {
                throw ItemStop(cancelled: false, message: "“\(existing.lastPathComponent)” can't be replaced "
                    + "because it contains the item being copied or moved.", done: [])
            }
            do {
                let inTrash = try trasher.trash(existing)
                trashed = (existing, inTrash)
                done.append(.trashed(original: existing, inTrash: inTrash))
            } catch {
                throw ItemStop(cancelled: false, message: FileSystem.message("replace", existing, error), done: [])
            }
        }
        do {
            switch mode {
            case .copy:
                let placed = try copyItem(job.source, to: destination, copier: copier)
                done.append(.created(placed))
            case .move:
                let placed = try moveItem(job.source, to: destination, sameVolume: job.sameVolume, copier: copier)
                done.append(.moved(from: job.source, to: placed))
            }
            return done
        } catch {
            var stop = Self.itemStop(error, verb: mode == .copy ? "copy" : "move", item: job.source)
            // The original stayed where it was after a copy across volumes; keep the copy as a new item.
            if let kept = error as? SourceKept { done.append(.created(kept.copy)) }
            // Put the replaced item back, so a failed or stopped copy loses nothing.
            if let trashed, !(error is SourceKept),
               (try? putBack(trashed.inTrash, at: trashed.original, copier: TreeCopier(cancel: CancelFlag(), tracker: nil))) != nil {
                done.removeAll { if case .trashed = $0 { return true } else { return false } }
            }
            stop = ItemStop(cancelled: stop.cancelled, message: stop.message, done: done)
            throw stop
        }
    }

    /// A move across volumes copied the item, but the original could not be removed.
    struct SourceKept: Error {
        let copy: URL
        let message: String
    }

    static func itemStop(_ error: Error, verb: String, item: URL) -> ItemStop {
        switch error {
        case TreeCopier.Failure.cancelled: return ItemStop(cancelled: true, message: "", done: [])
        case TreeCopier.Failure.failed(let message): return ItemStop(cancelled: false, message: message, done: [])
        case let kept as SourceKept: return ItemStop(cancelled: false, message: kept.message, done: [])
        default: return ItemStop(cancelled: false, message: FileSystem.message(verb, item, error), done: [])
        }
    }

    // MARK: Primitives (blocking)

    /// Copies `source` to a hidden temporary name next to `destination`, then renames it into place
    /// without replacing anything. Returns where it landed ("name (2)" if the name got taken meanwhile).
    func copyItem(_ source: URL, to destination: URL, copier: TreeCopier) throws -> URL {
        let folder = destination.deletingLastPathComponent()
        let temporary = folder.appendingPathComponent(".okno-partial-\(UUID().uuidString)", isDirectory: false)
        try copier.copy(source, to: temporary, cloning: allowsCloning)
        do {
            return try place(temporary, at: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)  // our own temporary copy
            throw error
        }
    }

    /// Moves an item: rename(2) on the same volume; else copy, and remove the original only
    /// after the copy fully succeeded. Throws `SourceKept` if the original could not be removed.
    func moveItem(_ source: URL, to destination: URL, sameVolume: Bool, copier: TreeCopier) throws -> URL {
        if sameVolume {
            do {
                return try place(source, at: destination)
            } catch let failure as FileSystem.POSIXFailure where failure.code == EXDEV {
                // Different volume after all (for example a mount point inside the folder): copy below.
            }
        }
        let placed = try copyItem(source, to: destination, copier: copier)
        do {
            try FileManager.default.removeItem(at: source)
        } catch {
            throw SourceKept(copy: placed, message: "“\(source.lastPathComponent)” was copied, but the original "
                + "could not be removed: \(FileSystem.message("remove", source, error))")
        }
        return placed
    }

    /// Renames `item` to `destination` without replacing anything. If the name is taken, uses
    /// "name (2)" instead. A case-only change of the same item is allowed. Returns the final URL.
    func place(_ item: URL, at destination: URL) throws -> URL {
        var target = destination
        for _ in 0..<10 {
            do {
                try FileSystem.renameNoReplace(item, to: target)
                return target
            } catch let failure as FileSystem.POSIXFailure where failure.code == EEXIST || failure.code == ENOTEMPTY {
                let folder = destination.deletingLastPathComponent()
                let name = Self.uniqueName(destination.lastPathComponent, in: folder, style: .numbered)
                target = folder.appendingPathComponent(name, isDirectory: destination.hasDirectoryPath)
            }
        }
        throw FileSystem.POSIXFailure(code: EEXIST)
    }

    /// Moves `item` back to `original`. If a different item has that name now, uses "name (2)".
    /// Makes the folder again if it is gone. Never replaces anything. Returns the final URL.
    func putBack(_ item: URL, at original: URL, copier: TreeCopier) throws -> URL {
        let folder = original.deletingLastPathComponent()
        if FileSystem.folderID(folder) == nil {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let isFolder = FileSystem.info(item)?.isFolder ?? false
        var destination = folder.appendingPathComponent(original.lastPathComponent, isDirectory: isFolder)
        if let there = FileSystem.info(destination), there.id != FileSystem.info(item)?.id {
            let name = Self.uniqueName(original.lastPathComponent, in: folder, style: .numbered)
            destination = folder.appendingPathComponent(name, isDirectory: isFolder)
        }
        let sameVolume = isSameVolume(item.deletingLastPathComponent(), folder)
        return try moveItem(item, to: destination, sameVolume: sameVolume, copier: copier)
    }
}
