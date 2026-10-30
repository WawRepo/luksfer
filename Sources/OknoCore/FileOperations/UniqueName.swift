import Foundation

/// How `FileOperationEngine.uniqueName` numbers a name that is taken.
public enum UniqueNameStyle: Sendable {
    /// "a.txt" → "a (2).txt" → "a (3).txt". New items and "Keep both".
    case numbered
    /// "a.txt" → "a copy.txt" → "a copy 2.txt". Duplicate and paste into the same folder.
    case copy
}

extension FileOperationEngine {
    /// `name` if nothing in `folder` has it, else the first free name in the style's sequence.
    /// A name that already ends in " (3)" or " copy 2" continues that sequence instead of stacking.
    /// Checks with lstat, so on a case-insensitive disk "A.txt" counts as taken by "a.txt".
    public static func uniqueName(_ name: String, in folder: URL, style: UniqueNameStyle) -> String {
        let existing = FileSystem.info(folder.appendingPathComponent(name, isDirectory: false))
        guard existing != nil else { return name }
        let isPlainFolder = existing?.isFolder == true && !isPackageName(name)
        let (base, ext) = isPlainFolder ? (name, "") : splitExtension(name)
        let root = stripCounter(base, style: style)
        var counter = style == .copy ? 1 : 2
        while true {
            let stem: String
            switch style {
            case .numbered: stem = "\(root) (\(counter))"
            case .copy: stem = counter == 1 ? "\(root) copy" : "\(root) copy \(counter)"
            }
            let candidate = ext.isEmpty ? stem : "\(stem).\(ext)"
            if !FileSystem.exists(folder.appendingPathComponent(candidate, isDirectory: false)) {
                return candidate
            }
            counter += 1
        }
    }

    /// Splits "report.final.pdf" into ("report.final", "pdf"). Hidden names like ".zshrc" and
    /// endings with spaces or over 10 characters ("v1.2 notes") count as no extension.
    static func splitExtension(_ name: String) -> (base: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        let ext = String(name[name.index(after: dot)...])
        guard !ext.isEmpty, ext.count <= 10, !ext.contains(" ") else { return (name, "") }
        return (String(name[..<dot]), ext)
    }

    /// Folders that macOS shows as one file keep their extension: "App.app" → "App copy.app".
    private static func isPackageName(_ name: String) -> Bool {
        let ext = splitExtension(name).ext.lowercased()
        return ["app", "bundle", "framework", "plugin", "pkg", "rtfd", "playground", "xcodeproj",
                "xcworkspace", "photoslibrary", "key", "pages", "numbers"].contains(ext)
    }

    /// "a (3)" → "a" for numbered; "a copy 2" or "a copy" → "a" for copy.
    private static func stripCounter(_ base: String, style: UniqueNameStyle) -> String {
        switch style {
        case .numbered:
            guard base.hasSuffix(")"), let open = base.range(of: " (", options: .backwards) else { return base }
            let digits = base[open.upperBound..<base.index(before: base.endIndex)]
            guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit), open.lowerBound != base.startIndex else {
                return base
            }
            return String(base[..<open.lowerBound])
        case .copy:
            if base.hasSuffix(" copy"), base.count > 5 { return String(base.dropLast(5)) }
            guard let range = base.range(of: " copy ", options: .backwards), range.lowerBound != base.startIndex
            else { return base }
            let digits = base[range.upperBound...]
            guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit) else { return base }
            return String(base[..<range.lowerBound])
        }
    }

    /// Throws `invalidName` for "", ".", "..", names with "/" or NUL, or over 255 UTF-8 bytes.
    static func validateName(_ name: String) throws {
        if name.isEmpty || name == "." || name == ".." || name.contains("/") || name.contains("\0")
            || name.utf8.count > 255 {
            throw FileOperationError.invalidName(name)
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
