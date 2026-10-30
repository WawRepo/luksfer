import Foundation

/// An SMB address as the user types it: `smb://server/share`, the Windows form `\\server\share`,
/// or just `server/share`. It may have a `user@`, a `:port` and a folder inside the share.
public struct SMBAddress: Equatable, Sendable {
    public var host: String
    public var port: Int?
    public var share: String
    /// A folder inside the share, with "/" between names; "" for the top of the share.
    public var folder: String
    public var user: String?

    public init(host: String, port: Int? = nil, share: String, folder: String = "", user: String? = nil) {
        self.host = host
        self.port = port
        self.share = share
        self.folder = folder
        self.user = user
    }

    /// Reads a typed address, or nil when it is not an SMB address with a server and a share.
    public static func parse(_ text: String) -> SMBAddress? {
        // Backslashes cannot be in server or share names, so they are always the Windows separator.
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\", with: "/")
        if let scheme = rest.range(of: "://") {
            guard rest[..<scheme.lowerBound].lowercased() == "smb" else { return nil }
            rest = String(rest[scheme.upperBound...])
        }
        let parts = rest.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }

        var authority = parts[0]
        var user: String?
        if let at = authority.lastIndex(of: "@") {
            // A password typed into the address ("user:password@server") is dropped, never kept.
            let name = String(authority[..<at].prefix { $0 != ":" })
            user = name.removingPercentEncoding ?? name
            authority = String(authority[authority.index(after: at)...])
        }
        var host = authority
        var port: Int?
        let portStart: String.Index?
        if authority.hasPrefix("[") {   // IPv6: [fe80::1]:445
            guard let close = authority.firstIndex(of: "]") else { return nil }
            host = String(authority[...close])
            let after = authority.index(after: close)
            guard after == authority.endIndex || authority[after] == ":" else { return nil }
            portStart = after == authority.endIndex ? nil : after
        } else {
            portStart = authority.lastIndex(of: ":")
            if let portStart { host = String(authority[..<portStart]) }
        }
        if let portStart {
            guard let number = Int(authority[authority.index(after: portStart)...]), (1...65535).contains(number) else { return nil }
            port = number
        }
        guard !host.isEmpty, host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }

        let names = parts.dropFirst().map { $0.removingPercentEncoding ?? $0 }
        let address = SMBAddress(host: host, port: port, share: names[0], folder: names.dropFirst().joined(separator: "/"),
                                 user: user?.isEmpty == false ? user : nil)
        guard URL(string: address.shareURLString) != nil else { return nil }
        return address
    }

    /// The share alone, which is what macOS mounts: `smb://server/share`, without the user.
    public var shareURL: URL { URL(string: shareURLString)! }

    /// The address to store and show: `smb://server/share/folder`, without the user.
    public var text: String {
        "smb://" + hostAndPort + "/" + ([share] + (folder.isEmpty ? [] : [folder])).joined(separator: "/")
    }

    /// True when both name the same share on the same server (names compare without case, like SMB).
    public func isSameShare(as other: SMBAddress) -> Bool {
        host.caseInsensitiveCompare(other.host) == .orderedSame && share.caseInsensitiveCompare(other.share) == .orderedSame
    }

    private var hostAndPort: String { host + (port.map { ":\($0)" } ?? "") }

    private var shareURLString: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return "smb://" + hostAndPort + "/" + (share.addingPercentEncoding(withAllowedCharacters: allowed) ?? share)
    }
}
