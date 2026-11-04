import Darwin
import Foundation
import UniformTypeIdentifiers

/// Lists a folder with `readdir` + `fstatat`. Reads names and metadata only, so a cloud folder
/// never downloads file contents because of a listing.
public enum DirectoryReader {
    /// `SF_DATALESS`: the file's data lives only in the cloud (File Provider).
    static let datalessFlag: UInt32 = 0x4000_0000

    public static func read(_ folder: URL, includeHidden: Bool) throws -> [FileItem] {
        // The app turns off downloads of cloud-only items for the whole process. A cloud folder
        // whose list is not on this Mac yet must still fetch its names, so allow that for this
        // thread while it lists. readdir and fstatat never read file contents.
        let previous = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_ON)
        defer { setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, previous >= 0 ? previous : IOPOL_MATERIALIZE_DATALESS_FILES_DEFAULT) }
        var items: [FileItem] = []
        try forEachEntry(in: folder, includeHidden: includeHidden) { item, _ in
            items.append(item)
            return true
        }
        return items
    }

    /// Calls `body` with each entry of a folder and its `stat`, until `body` returns false. It keeps
    /// the thread's download policy as it is.
    static func forEachEntry(in folder: URL, includeHidden: Bool, _ body: (FileItem, stat) -> Bool) throws {
        let path = folder.path
        guard let dir = opendir(path) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { closedir(dir) }
        let fd = dirfd(dir)
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            var st = stat()
            guard fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            let hidden = name.hasPrefix(".") || (st.st_flags & UInt32(UF_HIDDEN)) != 0
            if hidden && !includeHidden { continue }
            if !body(item(named: name, in: folder, stat: st, dirFD: fd, hidden: hidden), st) { return }
        }
    }

    /// Metadata for one path (used after a rename or a new item, and by tests).
    public static func item(at url: URL) -> FileItem? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        let name = url.lastPathComponent
        let hidden = name.hasPrefix(".") || (st.st_flags & UInt32(UF_HIDDEN)) != 0
        return item(named: name, in: url.deletingLastPathComponent(), stat: st, dirFD: AT_FDCWD, hidden: hidden, fullPath: url.path)
    }

    private static func item(named name: String, in folder: URL, stat st: stat, dirFD: Int32,
                             hidden: Bool, fullPath: String? = nil) -> FileItem {
        let mode = st.st_mode & S_IFMT
        let isLink = mode == S_IFLNK
        var isDir = mode == S_IFDIR
        if isLink {
            // A link to a folder opens like a folder. stat() follows the link; it reads metadata only.
            var target = stat()
            let ok = fullPath.map { stat($0, &target) } ?? fstatat(dirFD, name, &target, 0)
            isDir = ok == 0 && (target.st_mode & S_IFMT) == S_IFDIR
        }
        let ext = (name as NSString).pathExtension
        var type: UTType
        if isDir {
            let extType = FileTypes.folderType(forExtension: ext)
            type = extType.conforms(to: .package) ? extType : .folder
        } else if isLink && ext.isEmpty {
            type = .symbolicLink
        } else if ext.isEmpty && mode == S_IFREG && (st.st_mode & S_IXUSR) != 0 {
            type = .unixExecutable
        } else {
            type = FileTypes.type(forExtension: ext)
        }
        let isPackage = isDir && type != .folder
        return FileItem(
            url: folder.appendingPathComponent(name, isDirectory: isDir && !isPackage),
            name: name,
            isFolder: isDir && !isPackage,
            isPackage: isPackage,
            isSymlink: isLink,
            isHidden: hidden,
            isCloudOnly: (st.st_flags & datalessFlag) != 0,
            size: Int64(st.st_size),
            modified: Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9),
            created: Date(timeIntervalSince1970: Double(st.st_birthtimespec.tv_sec) + Double(st.st_birthtimespec.tv_nsec) / 1e9),
            type: type)
    }
}
