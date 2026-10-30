import Darwin
import Foundation

/// Small POSIX helpers for the file operation engine. All of them block; call them off the main thread.
enum FileSystem {
    /// Device and inode: equal values mean the same item on disk.
    struct ItemID: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    /// What `lstat` says about an item (links are not followed).
    struct ItemInfo {
        let id: ItemID
        let mode: mode_t
        let size: Int64

        var isFolder: Bool { (mode & S_IFMT) == S_IFDIR }
        var isRegularFile: Bool { (mode & S_IFMT) == S_IFREG }
    }

    /// A POSIX failure with its errno.
    struct POSIXFailure: Error {
        let code: Int32
        var message: String { String(cString: strerror(code)) }
    }

    static func path(_ url: URL) -> String { url.standardizedFileURL.path }

    /// `lstat` of an item, or nil when nothing is there.
    static func info(_ url: URL) -> ItemInfo? {
        var st = stat()
        guard lstat(path(url), &st) == 0 else { return nil }
        return ItemInfo(id: ItemID(device: st.st_dev, inode: st.st_ino), mode: st.st_mode, size: Int64(st.st_size))
    }

    /// `stat` (following links) of a folder, or nil.
    static func folderID(_ url: URL) -> ItemID? {
        var st = stat()
        guard stat(path(url), &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return nil }
        return ItemID(device: st.st_dev, inode: st.st_ino)
    }

    static func exists(_ url: URL) -> Bool { info(url) != nil }

    /// Renames without ever replacing an item that is already at `destination`.
    /// A case-only rename of the same item ("a.txt" to "A.txt") uses plain rename(2).
    static func renameNoReplace(_ source: URL, to destination: URL) throws {
        let src = path(source), dst = path(destination)
        if let target = info(destination), let item = info(source), target.id == item.id {
            // Same item under another spelling (case or Unicode form): rename(2) changes the spelling.
            guard rename(src, dst) == 0 else { throw POSIXFailure(code: errno) }
            return
        }
        guard renamex_np(src, dst, UInt32(RENAME_EXCL)) == 0 else { throw POSIXFailure(code: errno) }
    }

    /// Total bytes (regular files only) inside an item, counted with lstat. Links are not followed.
    static func treeBytes(_ url: URL) -> Int64 {
        guard let top = info(url) else { return 0 }
        if top.isRegularFile { return top.size }
        guard top.isFolder else { return 0 }
        var total: Int64 = 0
        var stack = [path(url)]
        while let folder = stack.popLast() {
            guard let dir = opendir(folder) else { continue }
            defer { closedir(dir) }
            let fd = dirfd(dir)
            while let entry = readdir(dir) {
                let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                    String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
                }
                if name == "." || name == ".." { continue }
                var st = stat()
                guard fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
                switch st.st_mode & S_IFMT {
                case S_IFREG: total += Int64(st.st_size)
                case S_IFDIR: stack.append(folder + "/" + name)
                default: break
                }
            }
        }
        return total
    }

    /// True when `folder` is `item` or lies somewhere inside it (links in `folder` resolved).
    static func isFolder(_ folder: URL, insideOf item: URL) -> Bool {
        guard let itemInfo = info(item), itemInfo.isFolder else { return false }
        var current = folder.resolvingSymlinksInPath().standardizedFileURL.path
        while true {
            if let id = folderID(URL(fileURLWithPath: current)), id == itemInfo.id { return true }
            if current == "/" || current.isEmpty { return false }
            current = (current as NSString).deletingLastPathComponent
        }
    }

    /// A short "Could not ... “name”: reason." message.
    static func message(_ verb: String, _ url: URL, _ error: Error) -> String {
        if let own = error as? FileOperationError, let text = own.errorDescription { return text }
        let reason: String
        if let failure = error as? POSIXFailure {
            reason = failure.message
        } else if let posix = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError,
                  posix.domain == NSPOSIXErrorDomain {
            reason = String(cString: strerror(Int32(posix.code)))
        } else {
            reason = (error as NSError).localizedFailureReason ?? error.localizedDescription
        }
        return "Could not \(verb) “\(url.lastPathComponent)”: \(reason)."
    }
}
