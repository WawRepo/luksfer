import AppKit

/// Keys the file list handles itself before NSTableView sees them.
enum ListKey {
    case open            // Enter (Windows keys) or ⌘↓
    case rename          // F2, or Enter with Finder keys
    case back            // Backspace
    case up              // ⌘↑
    case trash           // Del (fn-Delete)
    case deleteNow       // ⇧Del
    case quickLook       // Space
    case switchPane      // Tab
    case cancel          // Esc
}

protocol FileTableViewDelegate: AnyObject {
    func fileTable(_ table: FileTableView, handle key: ListKey) -> Bool
    func fileTable(_ table: FileTableView, menuForRows rows: IndexSet) -> NSMenu?
    func fileTableDidBecomeFirstResponder(_ table: FileTableView)
}

final class FileTableView: NSTableView {
    weak var keyDelegate: FileTableViewDelegate?
    var enterRenames = false

    override func keyDown(with event: NSEvent) {
        if let key = listKey(for: event), keyDelegate?.fileTable(self, handle: key) == true { return }
        super.keyDown(with: event)
    }

    private func listKey(for event: NSEvent) -> ListKey? {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let chars = event.charactersIgnoringModifiers, let c = chars.unicodeScalars.first else { return nil }
        switch Int(c.value) {
        case NSCarriageReturnCharacter, NSEnterCharacter:
            return flags.isEmpty ? (enterRenames ? .rename : .open) : nil
        case NSF2FunctionKey:
            return .rename
        case NSDownArrowFunctionKey where flags == .command:
            return .open
        case NSUpArrowFunctionKey where flags == .command:
            return .up
        case NSDeleteCharacter where flags.isEmpty:
            return .back
        case NSDeleteFunctionKey:
            return flags == .shift ? .deleteNow : (flags.isEmpty ? .trash : nil)
        case 0x20 where flags.isEmpty:
            return .quickLook
        case NSTabCharacter, NSBackTabCharacter:
            return flags.subtracting(.shift).isEmpty ? .switchPane : nil
        case 0x1B where flags.isEmpty:
            return .cancel
        default:
            return nil
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { keyDelegate?.fileTableDidBecomeFirstResponder(self) }
        return ok
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 {
            if !selectedRowIndexes.contains(row) { selectRowIndexes([row], byExtendingSelection: false) }
        } else {
            deselectAll(nil)
        }
        window?.makeFirstResponder(self)
        return keyDelegate?.fileTable(self, menuForRows: row >= 0 ? selectedRowIndexes : [])
    }

    // Clicking empty space below the rows clears the selection, like Explorer.
    override func mouseDown(with event: NSEvent) {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row < 0 { deselectAll(nil) }
        super.mouseDown(with: event)
    }
}
