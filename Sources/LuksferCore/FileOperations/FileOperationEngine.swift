import Darwin
import Foundation

/// Copies, moves, renames, creates and trashes items, and undoes each of these.
///
/// It never overwrites or deletes a user's item, except in `deletePermanently`: a replaced or
/// removed item goes to the Trash through `trasher`, so every change can be undone.
/// The async methods do their file work on a background queue, so they are safe to call from
/// the main actor. `rename`, `createFolder` and `createFile` are single quick system calls and
/// run on the caller's thread.
public final class FileOperationEngine: @unchecked Sendable {
    public typealias ClashResolver = @Sendable (NameClash) async -> ClashDecision
    public typealias ProgressHandler = @Sendable (OperationProgress) -> Void

    public let trasher: Trasher
    /// Clone on APFS instead of copying bytes when possible (instant, no extra space).
    /// Set before starting an operation. Tests turn it off to see byte progress.
    public var allowsCloning = true
    /// Whether two folders are on the same volume, so a move can be a rename.
    /// Set before starting an operation. Tests replace it to cover the copy-then-remove path.
    public var isSameVolume: @Sendable (URL, URL) -> Bool = { FileOperationEngine.volumesMatch($0, $1) }
    /// Shortest time between two progress reports while bytes are copied (item boundaries
    /// always report). Tests set 0 to see every report.
    public var progressInterval: TimeInterval = 0.05

    let queue = DispatchQueue(label: "luksfer.file-operations", qos: .userInitiated, attributes: .concurrent)

    public init(trasher: Trasher = SystemTrasher()) {
        self.trasher = trasher
    }

    /// True when both URLs report the same `volumeIdentifier`.
    public static func volumesMatch(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let va = try? a.resourceValues(forKeys: key).volumeIdentifier,
              let vb = try? b.resourceValues(forKeys: key).volumeIdentifier else { return false }
        return va.isEqual(vb)
    }

    // MARK: Rename and new items

    /// Renames an item in place. A case-only rename ("a.txt" → "A.txt") works on case-insensitive disks.
    public func rename(_ item: URL, to newName: String) throws -> FileChange {
        try Self.validateName(newName)
        guard let info = FileSystem.info(item) else { throw FileOperationError.sourceMissing(item.lastPathComponent) }
        if Array(newName.utf8) == Array(item.lastPathComponent.utf8) {
            return FileChange(actionName: "Rename", steps: [])
        }
        let target = item.deletingLastPathComponent().appendingPathComponent(newName, isDirectory: info.isFolder)
        if let other = FileSystem.info(target), other.id != info.id { throw FileOperationError.nameTaken(newName) }
        do {
            try FileSystem.renameNoReplace(item, to: target)
        } catch let failure as FileSystem.POSIXFailure where failure.code == EEXIST || failure.code == ENOTEMPTY {
            throw FileOperationError.nameTaken(newName)
        } catch {
            throw FileOperationError.failed(FileSystem.message("rename", item, error))
        }
        return FileChange(actionName: "Rename", steps: [.moved(from: item, to: target)])
    }

    /// Makes a new empty folder; a taken name becomes "New folder (2)".
    public func createFolder(in folder: URL, named name: String = "New folder") throws -> FileChange {
        try create(in: folder, named: name, action: "New Folder") { path in
            mkdir(path, 0o777) == 0 ? 0 : errno
        }
    }

    /// Makes a new file with `contents`; a taken name becomes "New text file (2).txt".
    public func createFile(in folder: URL, named name: String = "New text file.txt",
                           contents: Data = Data()) throws -> FileChange {
        try create(in: folder, named: name, action: "New File") { path in
            let fd = open(path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o666)
            guard fd >= 0 else { return errno }
            var code: Int32 = 0
            contents.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let written = write(fd, raw.baseAddress! + offset, raw.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        code = errno
                        return
                    }
                    offset += written
                }
            }
            if close(fd) != 0, code == 0 { code = errno }
            if code != 0 { unlink(path) }  // our own half-written new file
            return code
        }
    }

    /// Picks a free name and calls `make` (which returns 0 or an errno), retrying if the name got taken.
    private func create(in folder: URL, named name: String, action: String,
                        make: (String) -> Int32) throws -> FileChange {
        try Self.validateName(name)
        guard FileSystem.folderID(folder) != nil else { throw FileOperationError.sourceMissing(folder.lastPathComponent) }
        let isFolder = action == "New Folder"
        for _ in 0..<10 {
            let unique = Self.uniqueName(name, in: folder, style: .numbered)
            let url = folder.appendingPathComponent(unique, isDirectory: isFolder)
            let code = make(FileSystem.path(url))
            if code == 0 { return FileChange(actionName: action, steps: [.created(url)]) }
            if code == EEXIST { continue }
            throw FileOperationError.failed("Could not create “\(unique)”: \(String(cString: strerror(code))).")
        }
        throw FileOperationError.failed("Could not create “\(name)”: the name keeps being taken.")
    }

    // MARK: Trash and delete

    /// Moves items to the Trash. Undo puts them back.
    public func trash(_ items: [URL]) async throws -> FileChange {
        let items = Self.withoutNested(items)
        return try await onQueue {
            for item in items where !FileSystem.exists(item) {
                throw FileOperationError.sourceMissing(item.lastPathComponent)
            }
            var steps: [FileChange.Step] = []
            for item in items {
                do {
                    steps.append(.trashed(original: item, inTrash: try self.trasher.trash(item)))
                } catch {
                    throw Self.stopped(FileSystem.message("move to the Trash", item, error),
                                       action: "Move to Trash", steps: steps)
                }
            }
            return FileChange(actionName: "Move to Trash", steps: steps)
        }
    }

    /// Deletes items for good. There is no undo: the UI must ask first.
    /// Items that are already gone are passed over.
    public func deletePermanently(_ items: [URL]) async throws {
        let items = Self.withoutNested(items)
        try await onQueue {
            for item in items where FileSystem.exists(item) {
                do {
                    try FileManager.default.removeItem(at: item)
                } catch {
                    throw FileOperationError.failed(FileSystem.message("delete", item, error))
                }
            }
        }
    }

    // MARK: Helpers

    /// Runs blocking file work on the engine's queue, off the main thread and off Swift's thread pool.
    func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    /// The error for a failure after `steps` were done: `incomplete` with them, or `failed`.
    static func stopped(_ message: String, action: String, steps: [FileChange.Step]) -> FileOperationError {
        steps.isEmpty ? .failed(message) : .incomplete(message, partial: FileChange(actionName: action, steps: steps))
    }

    /// Drops duplicates and items that sit inside another listed item (moving the folder moves them).
    static func withoutNested(_ items: [URL]) -> [URL] {
        let paths = items.map { FileSystem.path($0) }
        var seen = Set<String>()
        var result: [URL] = []
        for (index, path) in paths.enumerated() {
            let nested = paths.contains { other in other != path && path.hasPrefix(other == "/" ? "/" : other + "/") }
            if !nested, seen.insert(path).inserted { result.append(items[index]) }
        }
        return result
    }
}
