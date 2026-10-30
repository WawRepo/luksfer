import Foundation

extension FileOperationEngine {
    /// Undoes a change and returns the change that redoes it (undo that one to redo).
    ///
    /// New items go to the Trash (never deleted), moved items move back, trashed items come back.
    /// When the original name is taken again, the item comes back as "name (2)". Items that no
    /// longer exist are passed over; the rest is undone, then one error names what was missing.
    /// Undo runs to the end and can't be stopped.
    public func undo(_ change: FileChange) async throws -> FileChange {
        try await onQueue { try self.undoNow(change) }
    }

    private func undoNow(_ change: FileChange) throws -> FileChange {
        var redo: [FileChange.Step] = []
        var missing: [String] = []
        let copier = TreeCopier(cancel: CancelFlag(), tracker: nil)
        for step in change.steps.reversed() {
            do {
                switch step {
                case .created(let url):
                    guard FileSystem.exists(url) else { missing.append(url.lastPathComponent); continue }
                    redo.append(.trashed(original: url, inTrash: try trasher.trash(url)))
                case .moved(let from, let to):
                    guard FileSystem.exists(to) else { missing.append(to.lastPathComponent); continue }
                    redo.append(.moved(from: to, to: try putBack(to, at: from, copier: copier)))
                case .trashed(let original, let inTrash):
                    guard FileSystem.exists(inTrash) else { missing.append(original.lastPathComponent); continue }
                    redo.append(.created(try putBack(inTrash, at: original, copier: copier)))
                }
            } catch {
                let message = Self.itemStop(error, verb: "undo", item: step.item).message
                throw Self.stopped(message, action: change.actionName, steps: redo)
            }
        }
        let result = FileChange(actionName: change.actionName, steps: redo)
        if missing.isEmpty { return result }
        if missing.count == 1, redo.isEmpty { throw FileOperationError.sourceMissing(missing[0]) }
        let list = missing.map { "“\($0)”" }.joined(separator: ", ")
        throw Self.stopped("Could not undo everything. These items can't be found: \(list).",
                           action: change.actionName, steps: redo)
    }
}

extension FileChange.Step {
    /// The item this step is about, for messages.
    var item: URL {
        switch self {
        case .created(let url): return url
        case .moved(_, let to): return to
        case .trashed(let original, _): return original
        }
    }
}
