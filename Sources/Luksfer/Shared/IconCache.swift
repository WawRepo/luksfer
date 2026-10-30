import AppKit
import LuksferCore
import UniformTypeIdentifiers

/// Icons for the list. Type icons only, so drawing an icon never reads a file (and never
/// downloads a cloud file). Exceptions that read local metadata only: app bundles outside cloud
/// folders and the special home folders (Desktop, Documents …).
final class IconCache {
    static let shared = IconCache()
    private var byType: [String: NSImage] = [:]
    private var byPath: [String: NSImage] = [:]
    private let specialFolders: Set<String> = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Set(["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public", "Applications", "Library"]
            .map { home.appendingPathComponent($0).path } + [home.path, "/Applications"])
    }()

    func icon(for item: FileItem) -> NSImage {
        if item.isFolder, specialFolders.contains(item.url.path) {
            return pathIcon(item.url.path)
        }
        if item.isPackage, item.type.conforms(to: .application), !item.isCloudOnly, !CloudPlaces.isInCloud(item.url) {
            return pathIcon(item.url.path)
        }
        let type = item.isFolder ? UTType.folder : item.type
        if let i = byType[type.identifier] { return i }
        let i = NSWorkspace.shared.icon(for: type)
        byType[type.identifier] = i
        return i
    }

    func folderIcon() -> NSImage { icon(forType: .folder) }

    func icon(forType type: UTType) -> NSImage {
        if let i = byType[type.identifier] { return i }
        let i = NSWorkspace.shared.icon(for: type)
        byType[type.identifier] = i
        return i
    }

    private func pathIcon(_ path: String) -> NSImage {
        if let i = byPath[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        byPath[path] = i
        return i
    }
}

/// Cloud storage folders (File Provider) under ~/Library/CloudStorage and iCloud Drive.
enum CloudPlaces {
    static let cloudStorage = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage", isDirectory: true)
    static let iCloudDrive = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)

    static func isInCloud(_ url: URL) -> Bool {
        url.path.hasPrefix(cloudStorage.path + "/") || url.path.hasPrefix(iCloudDrive.path)
    }

    /// (label, folder) for each cloud provider, e.g. ("Google Drive", …/GoogleDrive-x/My Drive).
    static func providers() -> [(String, URL)] {
        var out: [(String, URL)] = []
        let names = (try? FileManager.default.contentsOfDirectory(atPath: cloudStorage.path)) ?? []
        for name in names.sorted() where !name.hasPrefix(".") {
            let root = cloudStorage.appendingPathComponent(name, isDirectory: true)
            let provider = String(name.split(separator: "-").first ?? Substring(name))
            switch provider {
            case "GoogleDrive":
                let myDrive = root.appendingPathComponent("My Drive", isDirectory: true)
                out.append(("Google Drive", FileManager.default.fileExists(atPath: myDrive.path) ? myDrive : root))
            case "OneDrive": out.append(("OneDrive", root))
            case "Dropbox": out.append(("Dropbox", root))
            case "Box": out.append(("Box", root))
            default: out.append((provider, root))
            }
        }
        if FileManager.default.fileExists(atPath: iCloudDrive.path) { out.append(("iCloud Drive", iCloudDrive)) }
        // Two accounts of one provider: number them.
        var seen: [String: Int] = [:]
        return out.map { label, url in
            seen[label, default: 0] += 1
            return (seen[label]! > 1 ? "\(label) \(seen[label]!)" : label, url)
        }
    }
}
