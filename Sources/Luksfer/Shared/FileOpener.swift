import AppKit
import LuksferCore

/// Opens a file in its app. A self-test never launches another app: it only records the file, so a
/// check can see what Open would have handed to macOS.
@MainActor
enum FileOpener {
    private(set) static var recorded: [URL] = []

    static func open(_ url: URL) {
        if TestSwitches.isSelfTest() { recorded.append(url) } else { NSWorkspace.shared.open(url) }
    }
}
