import Foundation

/// Moves items to a Trash. The engine never deletes a user's item; it trashes it through this.
public protocol Trasher: Sendable {
    /// Moves the item to the Trash and returns its new location there.
    func trash(_ url: URL) throws -> URL
}

/// The real macOS Trash (`FileManager.trashItem`).
public struct SystemTrasher: Trasher {
    public init() {}

    public func trash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let inTrash = result as URL? else {
            throw FileOperationError.failed(
                "“\(url.lastPathComponent)” was moved to the Trash, but macOS did not say where, so it can't be put back.")
        }
        return inTrash
    }
}

/// A stand-in Trash for tests: moves items into `folder`, renaming to "name (2)" when taken.
public struct FolderTrasher: Trasher {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func trash(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let isFolder = FileSystem.info(url)?.isFolder ?? false
        for _ in 0..<5 {
            let name = FileOperationEngine.uniqueName(url.lastPathComponent, in: folder, style: .numbered)
            let target = folder.appendingPathComponent(name, isDirectory: isFolder)
            do {
                try FileSystem.renameNoReplace(url, to: target)
                return target
            } catch let failure as FileSystem.POSIXFailure where failure.code == EEXIST {
                continue
            }
        }
        throw FileOperationError.failed("Could not move “\(url.lastPathComponent)” to the Trash.")
    }
}
