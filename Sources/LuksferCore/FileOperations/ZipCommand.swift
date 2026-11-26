import Foundation

/// The `/usr/bin/zip` command for Compress with several items. Run it in `plan(_:)`'s folder.
public enum ZipCommand {
    public static let executable = URL(fileURLWithPath: "/usr/bin/zip")

    /// `--` and `./` keep a file name that starts with "-" from being read as an option:
    /// `-T` next to `-TT<command>` would make zip run the command. `-y` keeps links as links.
    /// A name can be a path below the folder (`deep/inner/a.txt`); the zip keeps that path.
    public static func arguments(zip: String, names: [String]) -> [String] {
        ["-r", "-y", "-q", zip, "--"] + names.map { "./" + $0 }
    }

    /// Where Compress puts the zip and what it names inside: the deepest folder that holds every
    /// item, and each item's path from that folder. Items from one folder give their names; search
    /// results from several folders keep their subfolder paths, so two files with the same name
    /// in different folders both go in.
    public static func plan(_ urls: [URL]) -> (folder: URL, paths: [String])? {
        let items = urls.map { $0.standardizedFileURL.pathComponents }
        guard var common = items.first?.dropLast().map({ $0 }) else { return nil }
        for parts in items.dropFirst() {
            let parent = parts.dropLast()
            var n = 0
            while n < common.count, n < parent.count, common[n] == parent[n] { n += 1 }
            common = Array(common.prefix(n))
        }
        let folder = URL(fileURLWithPath: NSString.path(withComponents: common), isDirectory: true)
        return (folder, items.map { $0.dropFirst(common.count).joined(separator: "/") })
    }

    /// A short reason from what zip or ditto printed when it failed, for the error message.
    /// zip exits with 18 when it could not read some items; it still writes a zip without them.
    public static func reason(output: String, status: Int32) -> String {
        guard var line = output.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces), !line.isEmpty else { return "" }
        for prefix in ["ditto: ", "zip error: ", "zip warning: ", "zip I/O error: "] where line.hasPrefix(prefix) {
            line.removeFirst(prefix.count)
        }
        // ditto names the whole path: keep only the item's name.
        if line.hasPrefix("/"), let split = line.range(of: ": ", options: .backwards) {
            line = (String(line[..<split.lowerBound]) as NSString).lastPathComponent + line[split.lowerBound...]
        }
        // zip names the whole path in brackets: keep only the name there too.
        if let open = line.range(of: "(/"), let close = line.range(of: ")", range: open.upperBound..<line.endIndex) {
            let path = String(line[line.index(after: open.lowerBound)..<close.lowerBound])
            line.replaceSubrange(open.lowerBound..<close.upperBound, with: "(\((path as NSString).lastPathComponent))")
        }
        if status == 18 { line = "Some items could not be read (\(line))" }
        return line.hasSuffix(".") ? line : line + "."
    }
}

/// Why Compress did not make a zip. The message is short English for the UI.
public enum CompressError: LocalizedError, Sendable, Equatable {
    case failed(zip: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .failed(let zip, let reason):
            let why = reason.isEmpty ? "The disk may be full, or an item may not be readable." : reason
            return "Luksfer could not make “\(zip)”. \(why)"
        }
    }
}
