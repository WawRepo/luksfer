import Foundation

/// One finished file action, with what the UI needs (selection, folders to refresh)
/// and the steps the engine needs to undo it. Pass it to `FileOperationEngine.undo(_:)`.
public struct FileChange: Sendable {
    /// For the Edit menu: "Copy", "Move", "Rename", "New Folder", "New File", "Duplicate", "Move to Trash".
    public let actionName: String
    /// Items that now exist because of this change, in order. The UI selects them.
    public let createdItems: [URL]
    /// Folders whose listing changed.
    public let touchedFolders: Set<URL>
    /// What was done, in order. Undo walks it backwards.
    let steps: [Step]

    /// True when nothing changed on disk (for example a move into the folder the items are in).
    /// The UI can skip registering an undo for it.
    public var isEmpty: Bool { steps.isEmpty }

    /// One change on disk.
    enum Step: Sendable {
        /// A new item exists at this URL. Undo moves it to the Trash.
        case created(URL)
        /// An item moved or was renamed. Undo moves it back.
        case moved(from: URL, to: URL)
        /// An item went to the Trash. Undo puts it back.
        case trashed(original: URL, inTrash: URL)
    }

    init(actionName: String, steps: [Step]) {
        self.actionName = actionName
        self.steps = steps
        var created: [URL] = []
        var folders = Set<URL>()
        for step in steps {
            switch step {
            case .created(let url):
                created.append(url)
                folders.insert(FileChange.parentFolder(of: url))
            case .moved(let from, let to):
                created.append(to)
                folders.insert(FileChange.parentFolder(of: from))
                folders.insert(FileChange.parentFolder(of: to))
            case .trashed(let original, let inTrash):
                created.removeAll { $0.path == original.path }
                folders.insert(FileChange.parentFolder(of: original))
                folders.insert(FileChange.parentFolder(of: inTrash))
            }
        }
        self.createdItems = created
        self.touchedFolders = folders
    }

    /// The folder an item is in, as a directory URL with a normalized path.
    static func parentFolder(of url: URL) -> URL {
        folderURL(url.deletingLastPathComponent())
    }

    /// A folder URL with a normalized path, so equal folders compare equal in a set.
    static func folderURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
    }
}
