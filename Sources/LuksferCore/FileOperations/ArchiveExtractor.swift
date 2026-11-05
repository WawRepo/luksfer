import Foundation

/// Extract for zip, 7z and tar files. A zip goes to macOS's `ditto`, which restores Mac file
/// attributes like Archive Utility does. The others go to macOS's `tar` (bsdtar), which also reads
/// 7z. Both run in a hidden folder next to the archive, so a failed extract leaves nothing behind
/// and a result never lands on an existing item.
///
/// Both tools keep bad entries inside that folder. `ditto` drops "..", reads "/x" as a relative path
/// and refuses to write through a link from the zip. `tar` reads "/x" as a relative path too, and
/// refuses an entry with ".." or one that goes through a link, which fails the whole extract. Both
/// drop setuid and pass a downloaded archive's quarantine mark on to the files, so macOS still
/// checks them. `ArchiveExtractorTests` holds them to all of that.
public enum ArchiveExtractor {
    public static let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
    public static let tar = URL(fileURLWithPath: "/usr/bin/tar")

    /// The endings Extract knows, with the tool for each. ".tar.gz" comes before ".tgz" and ".tar",
    /// and a lone ".gz" is not here: it is one compressed file, not an archive.
    private static let endings: [(ending: String, tool: URL)] = [
        (".zip", ditto), (".7z", tar),
        (".tar.gz", tar), (".tar.bz2", tar), (".tar.xz", tar),
        (".tgz", tar), (".tbz2", tar), (".txz", tar), (".tar", tar),
    ]

    public static func canExtract(_ item: FileItem) -> Bool {
        !item.isFolder && kind(of: item.name) != nil
    }

    private static func kind(of name: String) -> (ending: String, tool: URL)? {
        let lower = name.lowercased()
        return endings.first { lower.count > $0.ending.count && lower.hasSuffix($0.ending) }
    }

    /// Returns the new item next to the archive. The archive stays. One item at the top comes out
    /// as itself, and several come out in a folder named after the archive, like Archive Utility.
    /// Blocks until the tool ends, so call it off the main thread.
    public static func extract(_ archive: URL) throws -> URL {
        let fileName = archive.lastPathComponent
        guard let kind = kind(of: fileName) else { throw ArchiveExtractError.failed(fileName) }
        let fm = FileManager.default
        let folder = archive.deletingLastPathComponent()
        let work = folder.appendingPathComponent(".luksfer-extract-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: false)
        defer { removeAll(at: work) }

        try run(kind.tool, archive, into: work)

        let top = try fm.contentsOfDirectory(atPath: work.path).filter { $0 != ".DS_Store" }
        let source = top.count == 1 ? work.appendingPathComponent(top[0]) : work
        let name = top.count == 1 ? top[0] : folderName(fileName, without: kind.ending)
        let target = folder.appendingPathComponent(
            FileOperationEngine.uniqueName(name, in: folder, style: .numbered))
        try move(source, to: target)
        return target
    }

    /// "photos.tar.gz" gives "photos". The ending is plain ASCII, so it is as long in the real name
    /// as in the lowercased one.
    private static func folderName(_ fileName: String, without ending: String) -> String {
        let base = String(fileName.dropLast(ending.count))
        return base.allSatisfy { $0 == "." } ? "Extracted" : base
    }

    /// The archive's path is absolute, so it always starts with "/" and can never read as an option.
    private static func run(_ tool: URL, _ archive: URL, into work: URL) throws {
        let process = Process(), errors = Pipe()
        process.executableURL = tool
        process.arguments = tool == ditto
            ? ["-x", "-k", archive.path, work.path]
            : ["-x", "--no-fflags", "-f", archive.path, "-C", work.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            // ditto: "No password was provided". tar on a 7z: "The file content is encrypted" or
            // "The archive header is encrypted".
            if text.contains("No password was provided") || text.contains(" is encrypted") {
                throw ArchiveExtractError.needsPassword(archive.lastPathComponent)
            }
            throw ArchiveExtractError.failed(archive.lastPathComponent)
        }
    }

    /// `FileManager` refuses when the target exists, so a name taken since the check is an error,
    /// not an overwrite. macOS moves a folder to another parent only if the folder is writable,
    /// and an archive can hold a read-only one, so the move opens it up and then puts its mode back.
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

    /// Removes the hidden folder, and opens up read-only folders from the archive if that is needed.
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

/// Why an archive did not extract. Each has a short English message for the UI.
public enum ArchiveExtractError: LocalizedError, Sendable, Equatable {
    case needsPassword(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .needsPassword(let name): return "“\(name)” has a password. Luksfer cannot extract it."
        case .failed(let name): return "Luksfer could not extract “\(name)”. The file may be damaged, or the disk may be full."
        }
    }
}
