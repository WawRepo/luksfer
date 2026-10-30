import Foundation

/// The per-pane search box: keeps items whose name contains every typed word (any case and accent).
public enum ListFilter {
    public static func filter(_ items: [FileItem], query: String) -> [FileItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { item in
            words.allSatisfy { item.name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
