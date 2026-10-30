import Foundation

/// Folder autocomplete for the path bar.
public enum PathCompleter {
    /// Folder suggestions for the typed text: folders whose name starts with the typed last part
    /// (any case), packages left out, Finder order, at most `limit`. Names starting with "." only
    /// when the typed last part starts with "."; folders with the hidden flag (like ~/Library)
    /// only when at least one letter is typed.
    public static func suggestions(
        for text: String,
        relativeTo base: URL,
        limit: Int = 12,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        guard let query = Query(text, base: base, home: home) else { return [] }
        return query.matches().prefix(limit).map { query.parent.appendingPathComponent($0, isDirectory: true) }
    }

    /// What Tab inserts: the text with the single match completed and a trailing "/", or the
    /// longest common prefix of several matches. The typed folder part is kept as typed
    /// (so "~/Doc" becomes "~/Documents/"). Nil when there is nothing to add.
    public static func complete(
        _ text: String,
        relativeTo base: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        if text.trimmingCharacters(in: .whitespaces) == "~" { return text + "/" }
        guard let query = Query(text, base: base, home: home) else { return nil }
        let names = query.matches()
        guard let first = names.first else { return nil }
        let completed = names.count == 1 ? first + "/" : commonPrefix(names)
        guard completed.count >= query.typed.prefix.count else { return nil }
        let result = query.typed.head + query.typed.escaped(completed)
        return result == text ? nil : result
    }

    /// The typed text with its last part replaced by `name` and a "/": what Tab inserts for a
    /// chosen suggestion, and how the list shows it ("~/Pro" and "Projects" → "~/Projects/").
    public static func text(_ text: String, choosing name: String) -> String {
        let typed = TypedPath(text)
        return typed.head + typed.escaped(name) + "/"
    }

    /// The longest start shared by all names, compared without case; letters come from the first.
    static func commonPrefix(_ names: [String]) -> String {
        guard var prefix = names.first.map(Array.init) else { return "" }
        for name in names.dropFirst() {
            let chars = Array(name)
            var count = 0
            while count < prefix.count, count < chars.count,
                  String(prefix[count]).caseInsensitiveCompare(String(chars[count])) == .orderedSame {
                count += 1
            }
            prefix.removeLast(prefix.count - count)
        }
        return String(prefix)
    }
}

/// Typed text split into the part kept as typed and the last part being typed.
private struct TypedPath {
    /// The typed text up to and including the last "/", kept as typed (with an opening quote).
    let head: String
    /// The folder part to list, as typed ("" for the current folder).
    let folder: String
    /// The typed last part, unescaped, to match against folder names.
    let prefix: String
    let quote: Character?

    init(_ text: String) {
        var typed = String(text.drop(while: { $0 == " " || $0 == "\t" }))
        if typed == "~" { typed = "~/" }
        var body = typed
        let quote = PathResolver.stripQuotes(&body)
        let slash = body.lastIndex(of: "/")
        let namePart = slash.map { String(body[body.index(after: $0)...]) } ?? body
        var open = typed
        if body.count < typed.count - 1 { open.removeLast() }  // drop a closing quote
        head = String(open.dropLast(namePart.count))
        folder = slash.map { String(body[...$0]) } ?? ""
        prefix = PathResolver.unescape(namePart, quote: quote)
        self.quote = quote
    }

    /// `name` written so that the path bar reads it back unchanged (backslashes doubled outside quotes).
    func escaped(_ name: String) -> String {
        quote == nil ? name.replacingOccurrences(of: "\\", with: "\\\\") : name
    }
}

/// The folder to list and the prefix to match for some typed text.
private struct Query {
    let typed: TypedPath
    let parent: URL

    init?(_ text: String, base: URL, home: URL) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        typed = TypedPath(text)
        let parentText = (typed.quote.map(String.init) ?? "") + (typed.folder.isEmpty ? "." : typed.folder)
        parent = URL(fileURLWithPath: PathResolver.expand(parentText, relativeTo: base, home: home),
                     isDirectory: true)
    }

    /// Matching folder names in Finder order.
    func matches() -> [String] {
        let prefix = typed.prefix
        let showDot = prefix.hasPrefix(".")
        let showFlagged = !prefix.isEmpty
        let names = Subfolders.entries(in: parent)
            .filter { ($0.startsWithDot ? showDot : true) && ($0.hasHiddenFlag ? showFlagged : true) }
            .map(\.name)
            .filter { prefix.isEmpty || $0.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil }
        return Subfolders.sortedFinderOrder(names)
    }
}
