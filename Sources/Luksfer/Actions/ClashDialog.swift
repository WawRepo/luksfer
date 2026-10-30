import AppKit
import LuksferCore

/// Asks what to do when a copy or move meets an item with the same name (PRD §6.6).
enum ClashDialog {
    static func ask(_ clash: NameClash, window: NSWindow?, completion: @escaping (ClashDecision) -> Void) {
        let alert = NSAlert()
        let kind = clash.existingIsFolder ? "folder" : "file"
        alert.messageText = "A \(kind) named “\(clash.existing.lastPathComponent)” is already in “\(clash.existing.deletingLastPathComponent().displayName)”."
        alert.informativeText = [
            "New: \(describe(clash.source))",
            "Existing: \(describe(clash.existing))",
            "",
            "Replace puts the existing \(kind) in the Trash, so you can get it back.",
        ].joined(separator: "\n")
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        let stop = alert.addButton(withTitle: "Stop")
        stop.keyEquivalent = "\u{1b}"   // Esc stops the whole copy or move
        // "Do this for all" only when more clashes can follow.
        alert.showsSuppressionButton = clash.laterItems > 0
        alert.suppressionButton?.title = "Do this for all"
        let stopResponse = NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1)
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            let choice: ClashChoice
            switch response {
            case .alertSecondButtonReturn: choice = .replace
            case .alertThirdButtonReturn: choice = .skip
            case stopResponse: choice = .stop
            default: choice = .keepBoth
            }
            let all = alert.showsSuppressionButton && alert.suppressionButton?.state == .on
            completion(ClashDecision(choice: choice, applyToAll: all))
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
    }

    /// "12 KB, modified 30.10.2026, 18:40", or "folder, modified …". Reads metadata only (never a
    /// folder's size, which would mean listing everything inside it).
    private static func describe(_ url: URL) -> String {
        guard let item = DirectoryReader.item(at: url) else { return "can't be read" }
        let size = item.isFolder || item.isPackage ? "folder" : Formatters.size(item.size)
        return "\(size), modified \(Formatters.date.string(from: item.modified))"
    }
}
