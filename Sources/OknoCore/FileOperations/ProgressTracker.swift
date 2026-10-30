import Foundation

/// Set once when the Swift Task is cancelled; read from the copy thread.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

/// Counts bytes and items for one operation and reports them, at most once per `interval`
/// plus at every item boundary.
final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let handler: FileOperationEngine.ProgressHandler?
    private var progress: OperationProgress
    /// Bytes of items already finished; `progress.completedBytes` adds the current item's share.
    private var bytesBeforeItem: Int64 = 0
    private var currentItemBytes: Int64 = 0
    private var lastReport: UInt64 = 0
    private let interval: UInt64

    init(totalBytes: Int64, totalItems: Int, interval: TimeInterval, handler: FileOperationEngine.ProgressHandler?) {
        self.handler = handler
        self.interval = UInt64(max(0, interval) * 1_000_000_000)
        self.progress = OperationProgress(totalBytes: totalBytes, totalItems: totalItems)
    }

    var snapshot: OperationProgress { lock.withLock { progress } }

    /// A new top-level item starts; it has `bytes` to copy.
    func beginItem(name: String, bytes: Int64) {
        update(force: true) {
            currentItemBytes = bytes
            progress.completedBytes = bytesBeforeItem
            progress.currentName = name
        }
    }

    /// The current item has copied `copied` of its bytes so far.
    func itemCopied(_ copied: Int64, name: String) {
        update(force: false) {
            progress.completedBytes = bytesBeforeItem + min(max(copied, 0), currentItemBytes)
            progress.currentName = name
        }
    }

    /// The current item is done (copied, moved or skipped).
    func finishItem() {
        update(force: true) {
            bytesBeforeItem += currentItemBytes
            currentItemBytes = 0
            progress.completedBytes = bytesBeforeItem
            progress.completedItems += 1
        }
    }

    private func update(force: Bool, _ change: () -> Void) {
        var report: OperationProgress?
        lock.withLock {
            change()
            let now = DispatchTime.now().uptimeNanoseconds
            if force || now &- lastReport >= interval {
                lastReport = now
                report = progress
            }
        }
        if let report, let handler { handler(report) }
    }
}
