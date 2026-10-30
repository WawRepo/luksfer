import AppKit
import LuksferCore

extension NSDraggingInfo {
    /// Move or copy for dropping `urls` into `target` (PRD §6.7). A source that only allows copy
    /// (⌥ held, or an app that offers no move) copies; otherwise same volume moves, other volume
    /// copies, ⌥ copies and ⌘ moves.
    func fileOperation(for urls: [URL], into target: URL) -> DropOperation {
        let mask = draggingSourceOperationMask
        if !mask.contains(.move) && !mask.contains(.generic) { return .copy }
        let flags = NSEvent.modifierFlags
        let same = urls.first.map { DropRule.sameVolume($0, target) } ?? true
        return DropRule.operation(sameVolume: same, option: flags.contains(.option), command: flags.contains(.command))
    }

    /// The file URLs on the drag pasteboard.
    var fileURLs: [URL]? {
        draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    }
}
