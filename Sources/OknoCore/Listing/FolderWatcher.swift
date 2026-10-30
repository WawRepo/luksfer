import Foundation

/// Calls `onChange` (on the main queue, at most every 150 ms) when entries are added, removed or
/// renamed in a folder, and `onGone` when the folder itself is deleted or moved.
public final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending = false
    private let onChange: () -> Void
    private let onGone: () -> Void

    public init?(folder: URL, onChange: @escaping () -> Void, onGone: @escaping () -> Void) {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        self.onChange = onChange
        self.onGone = onGone
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .link, .attrib], queue: .main)
        src.setEventHandler { [weak self] in self?.handle(src.data) }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    deinit { source?.cancel() }

    private func handle(_ events: DispatchSource.FileSystemEvent) {
        if events.contains(.delete) || events.contains(.rename) {
            onGone()
            return
        }
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.pending = false
            self?.onChange()
        }
    }
}
