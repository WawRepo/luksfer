import Foundation

/// An outside terminal app that "Open in Terminal app" can open a folder in.
public enum TerminalApp: String, CaseIterable, Codable, Sendable {
    case terminal, iterm2, ghostty, warp

    /// The name shown in Settings and menus.
    public var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm2: return "iTerm2"
        case .ghostty: return "Ghostty"
        case .warp: return "Warp"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm2: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        case .warp: return "dev.warp.Warp-Stable"
        }
    }

    /// The URL to hand to the app so it opens a terminal in `folder`.
    ///
    /// Terminal, iTerm2 and Ghostty open a folder they are given: Terminal and iTerm2 in a new
    /// window, Ghostty in a new tab of its front window (a new window when it has none). Warp
    /// takes its own URL scheme: `warp://action/new_window?path=<folder>`.
    public func launchURL(forFolder folder: URL) -> URL {
        switch self {
        case .terminal, .iterm2, .ghostty:
            return folder
        case .warp:
            let path = Self.percentEncoded(folder.path)
            return URL(string: "warp://action/new_window?path=\(path)")!
        }
    }

    /// Percent-encodes every UTF-8 byte outside `A-Z a-z 0-9 - . _ ~ /`, so `&`, `+`, `#`, `?`,
    /// spaces and non-ASCII letters survive a query string.
    static func percentEncoded(_ path: String) -> String {
        var out = ""
        for byte in path.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"),
                 UInt8(ascii: "/"):
                out.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }
}
