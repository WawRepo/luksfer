import Foundation

/// A network drive the user set up (PRD §6.4). It has no password: the password lives in the
/// Keychain (`PasswordStore`), under `id`.
public struct NetworkDrive: Codable, Equatable, Sendable {
    public var id: String
    /// The label in the sidebar.
    public var name: String
    /// `smb://server/share`, maybe with a folder; never with a user or a password.
    public var address: String
    /// Empty for a guest connection.
    public var user: String

    public init(id: String = UUID().uuidString, name: String, address: String, user: String) {
        self.id = id
        self.name = name
        self.address = address
        self.user = user
    }

    public var smb: SMBAddress? { SMBAddress.parse(address) }
}

/// A mounted network volume (SMB, AFP, NFS, WebDAV).
public struct NetworkMount: Equatable, Sendable {
    public let mountPoint: URL
    /// Where it comes from, like `//user@server/share`.
    public let source: String
    /// The file system type, like `smbfs`.
    public let fileSystem: String

    public init(mountPoint: URL, source: String, fileSystem: String) {
        self.mountPoint = mountPoint
        self.source = source
        self.fileSystem = fileSystem
    }

    public static let networkFileSystems: Set<String> = ["smbfs", "afpfs", "nfs", "webdav"]

    /// The mounted network volumes now. Uses `getmntinfo` with `MNT_NOWAIT`, which never waits for a
    /// server, so a server that went away cannot freeze the window.
    public static func current() -> [NetworkMount] {
        var list: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&list, MNT_NOWAIT)
        guard count > 0, let list else { return [] }
        return (0..<Int(count)).compactMap { i in
            var fs = list[i]
            let type = string(&fs.f_fstypename)
            guard networkFileSystems.contains(type) else { return nil }
            return NetworkMount(mountPoint: URL(fileURLWithPath: string(&fs.f_mntonname), isDirectory: true),
                                source: string(&fs.f_mntfromname), fileSystem: type)
        }
    }

    /// True when this is the mounted share of `address`.
    public func isMount(of address: SMBAddress) -> Bool {
        guard fileSystem == "smbfs", let mounted = SMBAddress.parse(source) else { return false }
        return mounted.isSameShare(as: address)
    }

    /// The folder to open for `address` on this mount: the top of the share plus its folder.
    public func folder(for address: SMBAddress) -> URL {
        address.folder.isEmpty ? mountPoint : mountPoint.appendingPathComponent(address.folder, isDirectory: true)
    }

    private static func string<T>(_ field: inout T) -> String {
        withUnsafeBytes(of: &field) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
