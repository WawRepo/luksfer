import Foundation

/// What to do when an item with the same name already exists in the target folder.
public enum ClashChoice: Sendable, Equatable {
    /// Move the existing item to the Trash, then copy or move the new one in.
    case replace
    /// Leave both items alone; the new one is not copied or moved.
    case skip
    /// Copy or move the new item in as "name (2).ext".
    case keepBoth
    /// Stop the whole operation here. Items already done stay done and can be undone.
    case stop
}

/// The user's answer to one name clash.
public struct ClashDecision: Sendable, Equatable {
    public var choice: ClashChoice
    /// "Do this for all": use the same choice for every later clash in this operation.
    public var applyToAll: Bool

    public init(choice: ClashChoice, applyToAll: Bool = false) {
        self.choice = choice
        self.applyToAll = applyToAll
    }
}

/// A clash the UI must decide: `source` is about to land where `existing` already is.
public struct NameClash: Sendable {
    public let source: URL
    public let existing: URL
    public let sourceIsFolder: Bool
    public let existingIsFolder: Bool
    /// How many picked items come after this one. More clashes can follow only when it is above 0.
    public let laterItems: Int
}

/// Progress of a copy or move. Items are the top-level items the user picked;
/// bytes count every file inside them that must be copied (a same-disk move copies none).
public struct OperationProgress: Sendable, Equatable {
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var completedItems: Int
    public var totalItems: Int
    /// Name of the file being copied right now.
    public var currentName: String

    public init(completedBytes: Int64 = 0, totalBytes: Int64 = 0,
                completedItems: Int = 0, totalItems: Int = 0, currentName: String = "") {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.completedItems = completedItems
        self.totalItems = totalItems
        self.currentName = currentName
    }

    /// 0...1, by bytes when there are bytes to copy, else by items.
    public var fraction: Double {
        if totalBytes > 0 { return min(1, Double(completedBytes) / Double(totalBytes)) }
        if totalItems > 0 { return min(1, Double(completedItems) / Double(totalItems)) }
        return 1
    }
}

/// Errors from the file operation engine. Each has a short English message for the UI.
public enum FileOperationError: LocalizedError, Sendable {
    /// The name is empty, ".", "..", has "/" or NUL, or is over 255 UTF-8 bytes.
    case invalidName(String)
    /// Another item in the folder already has this name.
    case nameTaken(String)
    /// A folder cannot be copied or moved into itself or a folder inside it.
    case intoItself(String)
    /// The item (or folder) is gone.
    case sourceMissing(String)
    /// The task was cancelled. `partial` holds the items already done, so the UI can undo them.
    case cancelled(partial: FileChange?)
    /// Something failed before any change was made.
    case failed(String)
    /// Something failed part way. `partial` holds what was done, so the UI can still undo it.
    case incomplete(String, partial: FileChange)

    /// The part of the work that was done before the error, if any.
    public var partialChange: FileChange? {
        switch self {
        case .cancelled(let partial): return partial
        case .incomplete(_, let partial): return partial
        default: return nil
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            if name.isEmpty { return "A name can't be empty." }
            return "“\(name)” can't be used as a name. A name can't be “.” or “..”, contain “/”, "
                + "or be longer than 255 bytes."
        case .nameTaken(let name):
            return "An item named “\(name)” already exists in this folder."
        case .intoItself(let name):
            return "The folder “\(name)” can't be copied or moved into itself."
        case .sourceMissing(let name):
            return "“\(name)” can't be found. It may have been moved or deleted."
        case .cancelled:
            return "The operation was stopped."
        case .failed(let message), .incomplete(let message, _):
            return message
        }
    }
}
