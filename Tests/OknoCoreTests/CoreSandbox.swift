import Foundation

/// A fresh folder under ~/Library/Caches/okno-dev/sandbox/ for one test. Tests write nowhere else.
final class CoreSandbox {
    let root: URL

    init(_ name: String = #function) {
        let safe = name.filter { $0.isLetter || $0.isNumber }
        root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/okno-dev/sandbox/core-tests", isDirectory: true)
            .appendingPathComponent("\(safe)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func file(_ relative: String, _ contents: String = "") -> URL {
        let url = root.appendingPathComponent(relative)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(contents.utf8).write(to: url)
        return url
    }

    @discardableResult
    func folder(_ relative: String) -> URL {
        let url = root.appendingPathComponent(relative, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
