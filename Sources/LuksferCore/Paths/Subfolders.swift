import Darwin
import Foundation
import UniformTypeIdentifiers

/// Lists the folders directly inside a folder, by name only. It reads directory entries and
/// their attributes (`readdir` + `fstatat`), never file contents, so cloud folders do not download.
public enum Subfolders {
    /// A folder found inside another folder.
    public struct Entry: Equatable {
        public let name: String
        /// Has the hidden flag (like ~/Library or /usr). Names starting with "." are hidden too.
        public let hasHiddenFlag: Bool
        public var startsWithDot: Bool { name.hasPrefix(".") }
    }

    /// Every folder inside `folder`, packages (.app and the like) left out, in no order.
    /// Symbolic links to folders count as folders. An unreadable folder gives an empty list.
    public static func entries(in folder: URL) -> [Entry] {
        guard let dir = opendir(folder.path) else { return [] }
        defer { closedir(dir) }
        let fd = dirfd(dir)
        var result: [Entry] = []
        while let entry = readdir(dir) {
            let type = Int32(entry.pointee.d_type)
            guard type == DT_DIR || type == DT_LNK || type == DT_UNKNOWN else { continue }
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(length), as: UTF8.self)
            }
            if name == "." || name == ".." { continue }

            var info = stat()
            guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            var isFolder = (info.st_mode & S_IFMT) == S_IFDIR
            if (info.st_mode & S_IFMT) == S_IFLNK {
                var target = stat()
                isFolder = fstatat(fd, name, &target, 0) == 0 && (target.st_mode & S_IFMT) == S_IFDIR
            }
            guard isFolder, !isPackage(name: name) else { continue }
            let hidden = (info.st_flags & UInt32(UF_HIDDEN)) != 0
            result.append(Entry(name: name, hasHiddenFlag: hidden))
        }
        return result
    }

    /// The folders inside `folder` in Finder order. Hidden ones (dot names and the hidden flag)
    /// only when `includeHidden` is true.
    public static func list(in folder: URL, includeHidden: Bool = false) -> [URL] {
        let names = entries(in: folder)
            .filter { includeHidden || !($0.startsWithDot || $0.hasHiddenFlag) }
            .map(\.name)
        return sortedFinderOrder(names).map { folder.appendingPathComponent($0, isDirectory: true) }
    }

    /// Names sorted like Finder sorts them ("Item 2" before "Item 10", any case).
    public static func sortedFinderOrder(_ names: [String]) -> [String] {
        names.map { $0 as NSString }
            .sorted { $0.localizedStandardCompare($1 as String) == .orderedAscending }
            .map { $0 as String }
    }

    /// A folder whose extension makes it a package (shown as one file), like "Tool.app".
    /// Decided from the extension alone, so the disk is not touched.
    public static func isPackage(name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        return packageCache.value(for: ext) {
            UTType(filenameExtension: ext, conformingTo: .directory)?.conforms(to: .package) ?? false
        }
    }

    private static let packageCache = ExtensionCache()
}

/// A small thread-safe cache: file extension → "is a package".
private final class ExtensionCache: @unchecked Sendable {
    private var values: [String: Bool] = [:]
    private let lock = NSLock()

    func value(for ext: String, compute: () -> Bool) -> Bool {
        lock.lock()
        if let known = values[ext] { lock.unlock(); return known }
        lock.unlock()
        let computed = compute()
        lock.lock()
        values[ext] = computed
        lock.unlock()
        return computed
    }
}
