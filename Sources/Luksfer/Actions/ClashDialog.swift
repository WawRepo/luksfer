import AppKit
import LuksferCore

/// Asks what to do when a copy or move meets an item with the same name (PRD §6.6).
enum ClashDialog {
    static func ask(_ clash: NameClash, window: NSWindow?, completion: @escaping (ClashDecision) -> Void) {
        let alert = NSAlert()
        let kind = clash.existingIsFolder ? "folder" : "file"
        alert.messageText = "A \(kind) named “\(clash.existing.lastPathComponent)” is already in “\(clash.existing.deletingLastPathComponent().displayName)”."
        alert.informativeText = "Replace puts the existing \(kind) in the Trash, so you can get it back."
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do this for all"
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            let choice: ClashChoice
            switch response {
            case .alertSecondButtonReturn: choice = .replace
            case .alertThirdButtonReturn: choice = .skip
            default: choice = .keepBoth
            }
            completion(ClashDecision(choice: choice, applyToAll: alert.suppressionButton?.state == .on))
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
    }
}
