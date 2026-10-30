import Foundation
import UniformTypeIdentifiers

/// File types from the extension, and their display names, cached. Thread-safe.
public enum FileTypes {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var byExtension: [String: UTType] = [:]
    nonisolated(unsafe) private static var folderTypes: [String: UTType] = [:]
    nonisolated(unsafe) private static var names: [String: String] = [:]

    /// The type for a file name's extension. No disk access.
    public static func type(forExtension ext: String) -> UTType {
        let key = ext.lowercased()
        lock.lock()
        defer { lock.unlock() }
        if let t = byExtension[key] { return t }
        let t = key.isEmpty ? UTType.data : (UTType(filenameExtension: key) ?? .data)
        byExtension[key] = t
        return t
    }

    /// The type of a folder with this extension: a package type (`.app`, `.rtfd`) or a plain
    /// folder type. No disk access.
    public static func folderType(forExtension ext: String) -> UTType {
        let key = ext.lowercased()
        lock.lock()
        defer { lock.unlock() }
        if let t = folderTypes[key] { return t }
        let t = key.isEmpty ? UTType.folder : (UTType(filenameExtension: key, conformingTo: .directory) ?? .folder)
        folderTypes[key] = t
        return t
    }

    /// Explorer-style names for common extensions, where the system name is vague, lowercase or
    /// wrong for developers (`.ts` is TypeScript here, not an MPEG-2 stream).
    private static let common: [String: String] = [
        "txt": "Text document", "md": "Markdown document", "markdown": "Markdown document",
        "csv": "CSV file", "json": "JSON file", "yaml": "YAML file", "yml": "YAML file",
        "toml": "TOML file", "xml": "XML file", "html": "HTML document", "htm": "HTML document",
        "css": "CSS file", "js": "JavaScript file", "mjs": "JavaScript file", "jsx": "JavaScript React file",
        "ts": "TypeScript file", "tsx": "TypeScript React file", "py": "Python file", "rb": "Ruby file",
        "go": "Go file", "rs": "Rust file", "swift": "Swift file", "c": "C file", "h": "C header file",
        "cpp": "C++ file", "java": "Java file", "kt": "Kotlin file", "sh": "Shell script",
        "zsh": "Shell script", "bash": "Shell script", "sql": "SQL file", "log": "Log file",
        "pdf": "PDF document", "zip": "ZIP archive", "doc": "Word document", "docx": "Word document",
        "xls": "Excel workbook", "xlsx": "Excel workbook", "ppt": "PowerPoint presentation",
        "pptx": "PowerPoint presentation", "png": "PNG image", "jpg": "JPEG image", "jpeg": "JPEG image",
        "gif": "GIF image", "svg": "SVG image", "heic": "HEIC image", "mp3": "MP3 audio",
        "mp4": "MP4 video", "mov": "QuickTime movie", "dmg": "Disk image",
    ]

    /// Names for common files without an extension.
    private static let byFileName: [String: String] = [
        ".gitignore": "Git ignore file", ".gitattributes": "Git attributes file", ".env": "Environment file",
        ".editorconfig": "Editor settings file", ".zshrc": "Shell settings file", "makefile": "Makefile",
        "dockerfile": "Dockerfile", "license": "License file", "readme": "Read me file",
    ]

    /// "Folder", "PNG image", "Markdown document" … for the Type column.
    public static func displayName(for item: FileItem) -> String {
        if item.isFolder { return item.isSymlink ? "Folder alias" : "Folder" }
        if item.isSymlink && item.type == .symbolicLink { return "Alias" }
        let ext = item.fileExtension.lowercased()
        if let n = common[ext] { return n }
        if ext.isEmpty, let n = byFileName[item.name.lowercased()] { return n }
        let key = item.type.identifier
        lock.lock()
        defer { lock.unlock() }
        if let n = names[key] { return n }
        let n: String
        if item.type == .data || item.type.isDynamic {
            let ext = item.fileExtension
            n = ext.isEmpty ? "Document" : "\(ext.uppercased()) file"
        } else {
            // The system's names are often lowercase ("text", "shell script").
            let name = item.type.localizedDescription ?? "Document"
            n = name.prefix(1).uppercased() + name.dropFirst()
        }
        names[key] = n
        return n
    }
}
