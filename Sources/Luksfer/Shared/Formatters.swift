import AppKit

enum Formatters {
    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false   // "0 bytes", not "Zero KB"
        return f
    }()

    static func size(_ bytes: Int64) -> String { Formatters.bytes.string(fromByteCount: bytes) }
}

extension URL {
    /// The path with the home folder written as "~".
    var tildePath: String { (path as NSString).abbreviatingWithTildeInPath }

    var isRootFolder: Bool { standardizedFileURL.path == "/" }

    /// The display name used in titles and the sidebar ("Macintosh HD" for /).
    var displayName: String {
        if isRootFolder {
            return (try? resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? "Macintosh HD"
        }
        return FileManager.default.displayName(atPath: path)
    }
}

extension NSImage {
    static func symbol(_ name: String, _ label: String? = nil, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSImage {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: label) ?? NSImage()
        return img.withSymbolConfiguration(.init(pointSize: size, weight: weight)) ?? img
    }
}
