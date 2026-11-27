import Foundation

public enum SortKey: String, Codable, CaseIterable, Sendable {
    case name, modified, type, size, created, fileExtension
}

public struct FileSortOrder: Codable, Equatable, Sendable {
    public var key: SortKey
    public var ascending: Bool
    public init(key: SortKey = .name, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }

    /// The sort a pane of a new window starts with: Downloads by Date modified, newest first, so
    /// the latest download is at the top; any other folder by name.
    public static func newWindow(in folder: URL, downloads: URL) -> FileSortOrder {
        folder.standardizedFileURL.path == downloads.standardizedFileURL.path
            ? FileSortOrder(key: .modified, ascending: false) : FileSortOrder()
    }
}

/// Sorts a listing. Folders and files sort together as one list. With `foldersFirst` (Settings) it
/// sorts like Windows Explorer: folders come first in an ascending sort and last in a descending one
/// (the whole list turns around). A folder has no size, so a sort by size always keeps folders apart.
/// Names compare like Finder ("file 2" before "file 10").
public enum FileSorter {
    public static func sort(_ items: [FileItem], by order: FileSortOrder, foldersFirst: Bool) -> [FileItem] {
        // NSString compare is 40% faster than the same call on Swift String (spike).
        let names = items.map { $0.name as NSString }
        let typeNames = order.key == .type ? items.map { FileTypes.displayName(for: $0) as NSString } : []
        var indices = Array(items.indices)
        indices.sort { i, j in
            let a = items[i], b = items[j]
            if a.isFolder != b.isFolder, foldersFirst || order.key == .size { return a.isFolder == order.ascending }
            var result: ComparisonResult
            switch order.key {
            case .name: result = .orderedSame
            case .modified: result = compare(a.modified, b.modified)
            case .created: result = compare(a.created, b.created)
            case .size: result = a.isFolder ? .orderedSame : compare(a.size, b.size)
            case .type: result = typeNames[i].localizedStandardCompare(typeNames[j] as String)
            case .fileExtension: result = (a.fileExtension as NSString).localizedStandardCompare(b.fileExtension)
            }
            if result == .orderedSame { result = names[i].localizedStandardCompare(names[j] as String) }
            return order.ascending ? result == .orderedAscending : result == .orderedDescending
        }
        return indices.map { items[$0] }
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}
