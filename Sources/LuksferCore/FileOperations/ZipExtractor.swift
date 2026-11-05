import Foundation

/// Extract for zip files. It runs macOS's `ditto` in a hidden folder next to the zip, so a failed
/// extract leaves nothing behind and a result never lands on an existing item.
///
/// `ditto` keeps bad entries inside that folder: it drops "..", reads "/x" as a relative path and
/// refuses to write through a link from the zip. It also passes a downloaded zip's quarantine mark
/// on to the files, so macOS still checks them. `ZipExtractorTests` holds it to all of that.
public enum ZipExtractor {
    public static let executable = URL(fileURLWithPath: "/usr/bin/ditto")

    public static func canExtract(_ item: FileItem) -> Bool {
        !item.isFolder && item.fileExtension.lowercased() == "zip"
    }

    /// Returns the new item next to the zip. The zip stays. One item at the top of the zip comes
    /// out as itself, and several come out in a folder named after the zip, like Archive Utility.
    /// Blocks until `ditto` ends, so call it off the main thread.
    public static func extract(_ zip: URL) throws -> URL {
        let fm = FileManager.default
        let folder = zip.deletingLastPathComponent()
        let work = folder.appendingPathComponent(".luksfer-extract-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: false)
        defer { removeAll(at: work) }

        try runDitto(zip, into: work)

        let top = try fm.contentsOfDirectory(atPath: work.path).filter { $0 != ".DS_Store" }
        let source = top.count == 1 ? work.appendingPathComponent(top[0]) : work
        let name = top.count == 1 ? top[0] : folderName(for: zip)
        let target = folder.appendingPathComponent(
            FileOperationEngine.uniqueName(name, in: folder, style: .numbered))
        try move(source, to: target)
        return target
    }

    private static func folderName(for zip: URL) -> String {
        let base = zip.deletingPathExtension().lastPathComponent
        return base.allSatisfy { $0 == "." } ? "Extracted" : base
    }

    private static func runDitto(_ zip: URL, into work: URL) throws {
        let process = Process(), errors = Pipe()
        process.executableURL = executable
        process.arguments = ["-x", "-k", zip.path, work.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            if text.contains("No password was provided") { throw ZipExtractError.needsPassword(zip.lastPathComponent) }
            throw ZipExtractError.failed(zip.lastPathComponent)
        }
    }

    /// `FileManager` refuses when the target exists, so a name taken since the check is an error,
    /// not an overwrite. macOS moves a folder to another parent only if the folder is writable,
    /// and a zip can hold a read-only one, so the move opens it up and then puts its mode back.
    private static func move(_ source: URL, to target: URL) throws {
        let fm = FileManager.default
        var info = stat()
        guard lstat(source.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_mode & S_IWUSR == 0 else {
            try fm.moveItem(at: source, to: target)
            return
        }
        chmod(source.path, info.st_mode | S_IWUSR)
        try fm.moveItem(at: source, to: target)
        chmod(target.path, info.st_mode)
    }

    /// Removes the hidden folder, and opens up read-only folders from the zip if that is needed.
    private static func removeAll(at url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path), (try? fm.removeItem(at: url)) == nil else { return }
        chmod(url.path, 0o700)
        if let inside = fm.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let item as URL in inside {
                var info = stat()
                if lstat(item.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR { chmod(item.path, 0o700) }
            }
        }
        try? fm.removeItem(at: url)
    }
}

/// Why a zip did not extract. Each has a short English message for the UI.
public enum ZipExtractError: LocalizedError, Sendable, Equatable {
    case needsPassword(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .needsPassword(let name): return "“\(name)” has a password. Luksfer cannot extract it."
        case .failed(let name): return "Luksfer could not extract “\(name)”. The file may be damaged, or the disk may be full."
        }
    }
}
