import Darwin
import Foundation

/// Copies one item (file, folder tree or link) with copyfile(3), reports bytes,
/// and stops when the operation is cancelled. Blocks; run it off the main thread.
final class TreeCopier {
    enum Failure: Error {
        case cancelled
        case failed(String)
    }

    private let cancel: CancelFlag
    private let tracker: ProgressTracker?
    private var currentFile = ""
    private var currentName = ""
    private var currentFileCopied: Int64 = 0
    private var finishedBytes: Int64 = 0
    private var errorMessage: String?

    init(cancel: CancelFlag, tracker: ProgressTracker?) {
        self.cancel = cancel
        self.tracker = tracker
    }

    /// Copies `source` to `destination`, a fresh temporary path that belongs to the engine.
    /// Links stay links, metadata comes along, and APFS clones when `cloning` is on.
    /// On failure or cancel it removes whatever it made at `destination`, then throws.
    func copy(_ source: URL, to destination: URL, cloning: Bool) throws {
        currentFile = ""
        currentFileCopied = 0
        finishedBytes = 0
        errorMessage = nil
        if cancel.isCancelled { throw Failure.cancelled }

        guard let state = copyfile_state_alloc() else { throw Failure.failed("Could not start the copy.") }
        defer { copyfile_state_free(state) }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(treeCopierStatus, to: UnsafeRawPointer.self))
        var flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW | COPYFILE_EXCL)
        if cloning { flags |= copyfile_flags_t(COPYFILE_CLONE) }

        let src = FileSystem.path(source), dst = FileSystem.path(destination)
        let (result, code): (Int32, Int32) = withExtendedLifetime(self) {
            copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(self).toOpaque())
            // Copying a cloud-only file is the user's own action: allow the download on this thread only.
            return Self.withDatalessMaterialization {
                let result = copyfile(src, dst, state, flags)
                return (result, errno)
            }
        }
        // A copy that finished keeps its result even if cancel came at the very end;
        // the engine stops before the next item.
        guard result != 0 else { return }

        if FileSystem.exists(destination) { try? FileManager.default.removeItem(at: destination) }
        if cancel.isCancelled { throw Failure.cancelled }
        throw Failure.failed(errorMessage
            ?? "Could not copy “\(source.lastPathComponent)”: \(String(cString: strerror(code))).")
    }

    /// Runs `body` with cloud-only (dataless) files allowed to download on the calling thread,
    /// then restores the thread's previous policy. The app may forbid it for the whole process.
    static func withDatalessMaterialization<T>(_ body: () throws -> T) rethrows -> T {
        let type = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
        let previous = getiopolicy_np(type, IOPOL_SCOPE_THREAD)
        setiopolicy_np(type, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_ON)
        defer {
            setiopolicy_np(type, IOPOL_SCOPE_THREAD, previous >= 0 ? previous : IOPOL_MATERIALIZE_DATALESS_FILES_DEFAULT)
        }
        return try body()
    }

    /// Called by copyfile for every file start, data chunk, finish and error.
    fileprivate func status(what: Int32, stage: Int32, state: copyfile_state_t?, src: UnsafePointer<CChar>?) -> Int32 {
        let path = src.map { String(cString: $0) } ?? currentFile
        if stage == COPYFILE_ERR {
            let reason = String(cString: strerror(errno))
            errorMessage = "Could not copy “\((path as NSString).lastPathComponent)”: \(reason)."
            return COPYFILE_QUIT
        }
        switch (what, stage) {
        case (COPYFILE_RECURSE_FILE, COPYFILE_START):
            startFile(path)
            report()
        case (COPYFILE_COPY_DATA, COPYFILE_PROGRESS):
            if path != currentFile { startFile(path) }
            var copied: off_t = 0
            if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied) == 0 {
                currentFileCopied = Int64(copied)
            }
            report()
        case (COPYFILE_RECURSE_FILE, COPYFILE_FINISH):
            // Cloned files report no data chunks, so count the whole file when it is done.
            var st = stat()
            if lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG { finishedBytes += Int64(st.st_size) }
            currentFileCopied = 0
            currentFile = ""
            report()
        default:
            break
        }
        return cancel.isCancelled ? COPYFILE_QUIT : COPYFILE_CONTINUE
    }

    private func startFile(_ path: String) {
        currentFile = path
        currentName = (path as NSString).lastPathComponent
        currentFileCopied = 0
    }

    private func report() {
        tracker?.itemCopied(finishedBytes + currentFileCopied, name: currentName)
    }
}

/// The C status callback: forwards to the `TreeCopier` passed as context.
private let treeCopierStatus: copyfile_callback_t = { what, stage, state, src, _, context in
    guard let context else { return COPYFILE_CONTINUE }
    let copier = Unmanaged<TreeCopier>.fromOpaque(context).takeUnretainedValue()
    return copier.status(what: what, stage: stage, state: state, src: src)
}
