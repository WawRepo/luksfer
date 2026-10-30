import Foundation
import UniformTypeIdentifiers

/// File types from the extension, and their display names, cached. Thread-safe.
public enum FileTypes {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var byExtension: [String: UTType] = [:]
    nonisolated(unsafe) private static var folderTypes: [String: UTType] = [:]
    nonisolated(unsafe) private static var names: [String: String] = [:]

    /// The type for a file name's extension. No disk access.
    public static func type(forExtension ext: String) -> UTType {
        let key = ext.lowercased()
        lock.lock()
        defer { lock.unlock() }
        if let t = byExtension[key] { return t }
        let t = key.isEmpty ? UTType.data : (UTType(filenameExtension: key) ?? .data)
        byExtension[key] = t
        return t
    }

    /// The type of a folder with this extension: a package type (`.app`, `.rtfd`) or a plain
    /// folder type. No disk access.
    public static func folderType(forExtension ext: String) -> UTType {
        let key = ext.lowercased()
        lock.lock()
        defer { lock.unlock() }
        if let t = folderTypes[key] { return t }
        let t = key.isEmpty ? UTType.folder : (UTType(filenameExtension: key, conformingTo: .directory) ?? .folder)
        folderTypes[key] = t
        return t
    }

    /// "Folder", "PNG image", "Markdown document" … for the Type column.
    public static func displayName(for item: FileItem) -> String {
        if item.isFolder { return item.isSymlink ? "Folder alias" : "Folder" }
        if item.isSymlink && item.type == .symbolicLink { return "Alias" }
        let key = item.type.identifier
        lock.lock()
        defer { lock.unlock() }
        if let n = names[key] { return n }
        let n: String
        if item.type == .data || item.type.isDynamic {
            let ext = item.fileExtension
            n = ext.isEmpty ? "Document" : "\(ext.uppercased()) file"
        } else {
            n = item.type.localizedDescription ?? "Document"
        }
        names[key] = n
        return n
    }
}
