import Foundation

/// One part of the breadcrumb path: what it says and where it goes.
public struct PathCrumb: Equatable {
    public let title: String
    public let url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

/// Builds the breadcrumbs for a folder, the way the path bar shows them.
public enum PathCrumbs {
    /// Breadcrumbs for `folder`. Under `home`, the first crumb is the home folder titled
    /// `userName`; under /Volumes/X it is the volume X; anywhere else it is the startup disk
    /// (`rootName`). A cloud folder in ~/Library/CloudStorage (and iCloud Drive) shows as one crumb
    /// with the provider's name ("Google Drive"), never the account part of the folder name.
    public static func crumbs(for folder: URL, home: URL, userName: String, rootName: String) -> [PathCrumb] {
        let path = PathResolver.standardize(folder.path)
        let homePath = PathResolver.standardize(home.path)
        var result: [PathCrumb] = []
        var current: String
        var rest: [Substring]

        if homePath != "/" && (path == homePath || path.hasPrefix(homePath + "/")) {
            current = homePath
            result.append(crumb(userName, current))
            rest = path.dropFirst(homePath.count).split(separator: "/")
            if let cloud = cloudCrumb(rest) {
                current += "/" + rest.prefix(cloud.parts).joined(separator: "/")
                result.append(crumb(cloud.title, current))
                rest.removeFirst(cloud.parts)
            }
        } else if path.hasPrefix("/Volumes/") {
            let parts = path.split(separator: "/")
            current = "/Volumes/" + parts[1]
            result.append(crumb(String(parts[1]), current))
            rest = Array(parts.dropFirst(2))
        } else {
            current = "/"
            result.append(crumb(rootName, current))
            rest = path.split(separator: "/")
        }

        for part in rest {
            current = current == "/" ? "/" + part : current + "/" + part
            result.append(crumb(String(part), current))
        }
        return result
    }

    /// The display name for a folder inside ~/Library/CloudStorage, e.g. "GoogleDrive-<account>"
    /// → "Google Drive". The part after the first "-" (the account) is never used.
    public static func cloudProviderName(_ folderName: String) -> String {
        let provider = String(folderName.split(separator: "-", maxSplits: 1).first ?? Substring(folderName))
        switch provider {
        case "GoogleDrive": return "Google Drive"
        case "OneDrive": return "OneDrive"
        case "Dropbox": return "Dropbox"
        case "Box": return "Box"
        default: return splitWords(provider)
        }
    }

    // MARK: - Private

    private static func crumb(_ title: String, _ path: String) -> PathCrumb {
        PathCrumb(title: title, url: URL(fileURLWithPath: path, isDirectory: true))
    }

    /// The cloud folder at the start of a path below home, and how many path parts it covers.
    private static func cloudCrumb(_ parts: [Substring]) -> (title: String, parts: Int)? {
        guard parts.count >= 3, parts[0] == "Library" else { return nil }
        if parts[1] == "CloudStorage" { return (cloudProviderName(String(parts[2])), 3) }
        if parts[1] == "Mobile Documents" && parts[2] == "com~apple~CloudDocs" { return ("iCloud Drive", 3) }
        return nil
    }

    /// "ProtonDrive" → "Proton Drive"; a word of one letter stays joined ("pCloudDrive" → "pCloud Drive").
    private static func splitWords(_ name: String) -> String {
        var result = ""
        var wordLength = 0
        var previousWasLower = false
        for char in name {
            if char.isUppercase && previousWasLower && wordLength > 1 {
                result.append(" ")
                wordLength = 0
            }
            result.append(char)
            wordLength += 1
            previousWasLower = char.isLowercase
        }
        return result
    }
}
