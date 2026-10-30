import AppKit
import OknoCore

/// File changes started from the UI. Filled in by the file operation engine.
final class FileActions {
    static let shared = FileActions()

    func rename(_ url: URL, to name: String, in window: BrowserWindowController) { NSSound.beep() }
    func transfer(_ urls: [URL], into folder: URL, operation: DropOperation, in window: BrowserWindowController) { NSSound.beep() }
    func cancelCurrent() {}
}
