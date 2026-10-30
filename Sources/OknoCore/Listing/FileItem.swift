import Foundation
import UniformTypeIdentifiers

/// One entry of a folder listing.
///
/// Built from `readdir` + `fstatat`, never from URL resource keys: the spike measured the cloud
/// keys at 725 ms per 10,000 items against 22 ms for `fstatat` (docs/spike-report.md).
public struct FileItem: Hashable, Sendable {
    public let url: URL
    public let name: String
    /// A folder Okno opens itself. Packages (`.app`, `.rtfd`) and files are not folders.
    public let isFolder: Bool
    public let isPackage: Bool
    public let isSymlink: Bool
    public let isHidden: Bool
    /// Only in the cloud: the file has no local data (`SF_DATALESS`). Reading it would download it.
    public let isCloudOnly: Bool
    public let size: Int64
    public let modified: Date
    public let created: Date
    public let type: UTType

    public init(url: URL, name: String, isFolder: Bool, isPackage: Bool, isSymlink: Bool,
                isHidden: Bool, isCloudOnly: Bool, size: Int64, modified: Date, created: Date,
                type: UTType) {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.isPackage = isPackage
        self.isSymlink = isSymlink
        self.isHidden = isHidden
        self.isCloudOnly = isCloudOnly
        self.size = size
        self.modified = modified
        self.created = created
        self.type = type
    }

    /// The file extension as shown in the Extension column ("" for folders).
    public var fileExtension: String { isFolder ? "" : (name as NSString).pathExtension }

    public static func == (a: FileItem, b: FileItem) -> Bool { a.url == b.url && a.modified == b.modified && a.size == b.size && a.name == b.name }
    public func hash(into hasher: inout Hasher) { hasher.combine(url) }
}
