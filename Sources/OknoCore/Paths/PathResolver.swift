import Foundation

/// Turns text typed or pasted into the path bar into a place to go.
public enum PathResolver {
    /// Words that open a terminal in the current folder (compared trimmed, any case).
    public static let terminalWords: Set<String> = ["term", "terminal", "cmd"]

    /// What `text` asks for. `base` is the pane's current folder (for relative paths).
    /// Reads only the item's own attributes (a `stat`), never its contents.
    public static func resolve(
        _ text: String,
        relativeTo base: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> PathInput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if terminalWords.contains(trimmed.lowercased()) { return .openTerminal }

        let path = expand(text, relativeTo: base, home: home)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            let name = (path as NSString).lastPathComponent
            if isDirectory.boolValue && !Subfolders.isPackage(name: name) {
                return .folder(URL(fileURLWithPath: path, isDirectory: true))
            }
            return .file(URL(fileURLWithPath: path, isDirectory: isDirectory.boolValue))
        }
        // A broken symbolic link still exists as an item that can be selected.
        if (try? fileManager.attributesOfItem(atPath: path)) != nil {
            return .file(URL(fileURLWithPath: path, isDirectory: false))
        }
        return .notFound("No folder or file at \(abbreviate(path, home: home))")
    }

    /// Typed text → absolute standardized path, without touching the disk. Handles surrounding
    /// quotes ('…' "…" “…”), backslash escapes pasted from a terminal ("\ "), "~", "~/…" and
    /// "~user/…", file:// URLs, relative paths (".", "..", plain names), and extra slashes.
    public static func expand(
        _ text: String,
        relativeTo base: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        var path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let quote = stripQuotes(&path)
        if path.range(of: "file://", options: [.caseInsensitive, .anchored]) != nil {
            path = pathFromFileURL(path)
        } else {
            path = unescape(path, quote: quote)
        }
        path = expandTilde(path, home: home)
        if !path.hasPrefix("/") { path = base.path + "/" + path }
        return standardize(path)
    }

    /// `path` with the home folder shown as "~" (for messages).
    public static func abbreviate(_ path: String, home: URL) -> String {
        let homePath = standardize(home.path)
        guard homePath != "/" else { return path }
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }

    /// Removes ".", resolves "..", and drops empty, duplicate and trailing slashes.
    /// Does not follow symbolic links.
    public static func standardize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    // MARK: - Steps

    private static let quotePairs: [Character: Character] = ["'": "'", "\"": "\"", "“": "”", "‘": "’"]

    /// Strips a leading quote and its matching closing quote (if there is one); returns the quote.
    /// A missing closing quote is allowed, so half-typed text still works.
    static func stripQuotes(_ text: inout String) -> Character? {
        guard let open = text.first, let close = quotePairs[open] else { return nil }
        text.removeFirst()
        if text.last == close { text.removeLast() }
        return open
    }

    /// Shell-style backslash escapes: all of them outside quotes, only \" \\ \$ \` inside double
    /// quotes, none inside single or typographic quotes.
    static func unescape(_ text: String, quote: Character?) -> String {
        guard text.contains("\\"), quote == nil || quote == "\"" else { return text }
        let escapable: Set<Character> = ["\"", "\\", "$", "`"]
        var result = ""
        var escaping = false
        for char in text {
            if escaping {
                if quote != nil && !escapable.contains(char) { result.append("\\") }
                result.append(char)
                escaping = false
            } else if char == "\\" {
                escaping = true
            } else {
                result.append(char)
            }
        }
        return result
    }

    static func pathFromFileURL(_ text: String) -> String {
        if let url = URL(string: text), url.isFileURL, !url.path.isEmpty { return url.path }
        var rest = String(text.dropFirst("file://".count))
        if rest.lowercased().hasPrefix("localhost/") { rest = String(rest.dropFirst("localhost".count)) }
        return rest.removingPercentEncoding ?? rest
    }

    static func expandTilde(_ text: String, home: URL) -> String {
        guard text.hasPrefix("~") else { return text }
        let slash = text.firstIndex(of: "/") ?? text.endIndex
        let user = text[text.index(after: text.startIndex)..<slash]
        let rest = text[slash...]
        if user.isEmpty { return home.path + rest }
        if let userHome = FileManager.default.homeDirectory(forUser: String(user)) {
            return userHome.path + rest
        }
        return text
    }
}
