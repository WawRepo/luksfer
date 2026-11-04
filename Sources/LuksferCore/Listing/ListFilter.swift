import Foundation

/// The per-pane search box: keeps items whose name contains every typed word (any case and accent).
public enum ListFilter {
    public static func filter(_ items: [FileItem], query: String) -> [FileItem] {
        let typed = words(in: query)
        guard !typed.isEmpty else { return items }
        return items.filter { matches($0.name, words: typed) }
    }

    public static func words(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public static func matches(_ name: String, words: [String]) -> Bool {
        words.allSatisfy { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
