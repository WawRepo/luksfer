import Foundation

public enum DropOperation: Equatable, Sendable { case move, copy }

/// What a drag and drop does (PRD §6.6): same disk moves, other disk copies, ⌥ forces copy,
/// ⌘ forces move.
public enum DropRule {
    public static func operation(sameVolume: Bool, option: Bool, command: Bool) -> DropOperation {
        if option { return .copy }
        if command { return .move }
        return sameVolume ? .move : .copy
    }

    /// Whether two file URLs are on the same volume. Reads volume ids only.
    public static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key = URLResourceKey.volumeIdentifierKey
        guard let va = try? a.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject,
              let vb = try? b.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject else { return false }
        return va.isEqual(vb)
    }
}
