import Foundation

/// OSC 7, the escape code a shell sends to report its folder: `ESC ] 7 ; file://host/path BEL`,
/// with the path percent-encoded.
public enum OSC7 {
    /// The folder in an OSC 7 payload: `file://host/a%20b` → `/a b`. Nil for anything that is
    /// not a `file://` URL with an absolute path, or has a broken percent escape.
    public static func folder(fromPayload payload: String) -> URL? {
        guard let parts = split(payload),
              let path = parts.path.removingPercentEncoding,
              path.hasPrefix("/"), !path.contains("\0")
        else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The host in an OSC 7 payload (`""` when there is none). Nil when it is not a `file://` URL.
    public static func host(fromPayload payload: String) -> String? {
        split(payload)?.host
    }

    /// Whether `host` names this Mac: empty, `localhost`, or the same name as `localHostName`
    /// compared without the domain, ignoring case. A shell on another machine (ssh) sends its own
    /// host name; Okno must not open that path here.
    public static func isLocal(host: String, localHostName: String) -> Bool {
        if host.isEmpty || host.caseInsensitiveCompare("localhost") == .orderedSame { return true }
        func label(_ name: String) -> String {
            String(name.split(separator: ".", maxSplits: 1).first ?? "").lowercased()
        }
        return !label(host).isEmpty && label(host) == label(localHostName)
    }

    private static func split(_ payload: String) -> (host: String, path: String)? {
        let scheme = "file://"
        guard payload.count > scheme.count,
              payload.prefix(scheme.count).lowercased() == scheme
        else { return nil }
        let rest = payload.dropFirst(scheme.count)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        return (String(rest[..<slash]), String(rest[slash...]))
    }
}
