import AppKit

/// A drag for the self-test: file URLs on a private pasteboard, never the user's clipboard.
/// `mask` stands in for the keys held (⌥ limits a drag to copy).
final class SelfTestDrag: NSObject, NSDraggingInfo {
    private static var count = 0
    let draggingPasteboard: NSPasteboard
    let draggingSourceOperationMask: NSDragOperation
    let draggingSource: Any? = nil

    init(_ urls: [URL], mask: NSDragOperation = [.copy, .move, .generic]) {
        SelfTestDrag.count += 1
        draggingPasteboard = NSPasteboard(name: .init("app.okno.selftest.drag\(SelfTestDrag.count)"))
        draggingPasteboard.clearContents()
        draggingPasteboard.writeObjects(urls.map { $0 as NSURL })
        draggingSourceOperationMask = mask
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSequenceNumber: Int { SelfTestDrag.count }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
