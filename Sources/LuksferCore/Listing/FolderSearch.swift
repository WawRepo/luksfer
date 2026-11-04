import Darwin
import Foundation

/// Finds items by name in a folder and its subfolders (PRD §5.3). It reads names and metadata with
/// `readdir` + `fstatat`, nearest folders first, and never starts a download: downloads stay off
/// for its thread, and it does not open a folder whose list is only in the cloud.
public final class FolderSearch: @unchecked Sendable {
    public struct Stats: Equatable, Sendable {
        public var foldersSearched = 0
        /// Not opened: the folder's list is only in the cloud, and opening it would fetch the list.
        public var cloudOnlyFolders = 0
        /// Not opened: no permission, or a read error.
        public var unreadableFolders = 0
        /// Not opened: another disk or a network drive mounted inside the folder.
        public var otherVolumes = 0
        /// The search stopped at `limit` results.
        public var reachedLimit = false

        public init() {}

        public var foldersNotSearched: Int { cloudOnlyFolders + unreadableFolders + otherVolumes }
    }

    /// What the search does with a folder it finds.
    enum Decision: Equatable { case enter, skipLink, skipCloudOnly, skipOtherVolume }

    /// More results than this do not help anyone; type more words instead.
    public static let defaultLimit = 20_000

    public let root: URL
    private let words: [String]
    private let includeHidden: Bool
    private let limit: Int
    private let lock = NSLock()
    private var cancelled = false

    public init(root: URL, query: String, includeHidden: Bool, limit: Int = FolderSearch.defaultLimit) {
        self.root = root
        self.words = ListFilter.words(in: query)
        self.includeHidden = includeHidden
        self.limit = limit
    }

    /// Stops the search. A call to the disk that has started still has to return first.
    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// Walks the folder on the calling thread and returns when it ends. `onBatch` runs on the same
    /// thread with new results, at most once per `interval` seconds.
    @discardableResult
    public func run(every interval: TimeInterval = 0.15, onBatch: ([FileItem], Stats) -> Void) -> Stats {
        var stats = Stats()
        guard !words.isEmpty else { return stats }
        let previous = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        defer { setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, previous >= 0 ? previous : IOPOL_MATERIALIZE_DATALESS_FILES_DEFAULT) }

        var rootStat = stat()
        guard stat(root.path, &rootStat) == 0 else {
            stats.unreadableFolders = 1
            return stats
        }
        var queue: [(url: URL, device: dev_t)] = [(root, rootStat.st_dev)]
        var next = 0
        var batch: [FileItem] = []
        var found = 0
        var lastSent = ProcessInfo.processInfo.systemUptime

        while next < queue.count, !stats.reachedLimit, !isCancelled {
            let folder = queue[next]
            next += 1
            if next > 4096 { queue.removeFirst(next); next = 0 }
            do {
                try DirectoryReader.forEachEntry(in: folder.url, includeHidden: includeHidden) { item, st in
                    if isCancelled { return false }
                    if item.isFolder {
                        switch Self.decision(for: item, device: st.st_dev, parentDevice: folder.device) {
                        case .enter: queue.append((item.url, st.st_dev))
                        case .skipLink: break
                        case .skipCloudOnly: stats.cloudOnlyFolders += 1
                        case .skipOtherVolume: stats.otherVolumes += 1
                        }
                    }
                    if ListFilter.matches(item.name, words: words) {
                        batch.append(item)
                        found += 1
                        if found >= limit {
                            stats.reachedLimit = true
                            return false
                        }
                    }
                    let now = ProcessInfo.processInfo.systemUptime
                    if !batch.isEmpty, now - lastSent >= interval {
                        onBatch(batch, stats)
                        batch = []
                        lastSent = now
                    }
                    return true
                }
                stats.foldersSearched += 1
            } catch {
                stats.unreadableFolders += 1
            }
        }
        if !batch.isEmpty, !isCancelled { onBatch(batch, stats) }
        return stats
    }

    /// Links can make a loop, so the search never follows one. Another device number does not prove
    /// another disk, so the search asks if the folder is a mount point. `/System/Volumes` shows the
    /// files of `/` again under other paths, and on a Mac it has the same device number as `/`.
    static func decision(for item: FileItem, device: dev_t, parentDevice: dev_t) -> Decision {
        if item.isSymlink { return .skipLink }
        if item.isCloudOnly { return .skipCloudOnly }
        if item.url.path == "/System/Volumes" { return .skipOtherVolume }
        if device != parentDevice, isMountPoint(item.url.path) { return .skipOtherVolume }
        return .enter
    }

    static func isMountPoint(_ path: String) -> Bool {
        var fs = statfs()
        guard statfs(path, &fs) == 0, let real = realpath(path, nil) else { return false }
        defer { free(real) }
        let mountedOn = withUnsafePointer(to: &fs.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return mountedOn == String(cString: real)
    }

    // MARK: Paths of results

    /// Whether `url` lies somewhere inside `folder`.
    public static func isInside(_ url: URL, folder: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(prefix(of: folder))
    }

    /// The text of the Folder column: the searched folder's name, then the way down to the item.
    public static func location(of url: URL, under root: URL) -> String {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if parent == rootPath { return root.lastPathComponent }
        let start = prefix(of: root)
        guard parent.hasPrefix(start) else { return parent }
        let rest = parent.dropFirst(start.count)
        return rootPath == "/" ? "/" + rest : root.lastPathComponent + "/" + rest
    }

    private static func prefix(of folder: URL) -> String {
        let path = folder.standardizedFileURL.path
        return path == "/" ? "/" : path + "/"
    }
}
