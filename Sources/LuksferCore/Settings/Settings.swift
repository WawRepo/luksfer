import Foundation

/// A pinned folder in the sidebar. The label can be renamed; the path stays.
public struct Favorite: Codable, Equatable, Sendable {
    public var path: String
    public var label: String
    public init(path: String, label: String) {
        self.path = path
        self.label = label
    }
    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

public enum KeyMode: String, Codable, CaseIterable, Sendable {
    /// Enter opens, F2 renames (the default).
    case windows
    /// Enter renames, ⌘↓ opens.
    case finder
}

public struct ColumnState: Codable, Equatable, Sendable {
    public var id: String
    public var width: Double
    public var hidden: Bool
    public init(id: String, width: Double, hidden: Bool) {
        self.id = id
        self.width = width
        self.hidden = hidden
    }
}

public struct PaneState: Codable, Equatable, Sendable {
    public var path: String
    public var sort: FileSortOrder
    public init(path: String, sort: FileSortOrder = FileSortOrder()) {
        self.path = path
        self.sort = sort
    }
}

public struct WindowState: Codable, Equatable, Sendable {
    public var frame: String?            // NSStringFromRect
    public var twoPanes: Bool = false
    public var panes: [PaneState]
    public var activePane: Int = 0
    public var terminalOpen: Bool = false
    public var terminalHeight: Double = 240
    public var sidebarWidth: Double = 200
    public init(panes: [PaneState]) { self.panes = panes }
}

/// Everything Luksfer remembers. Stored as JSON in ~/Library/Application Support/Luksfer/.
public struct AppSettings: Codable, Equatable, Sendable {
    public var favorites: [Favorite] = []
    public var showHidden = false
    public var keyMode: KeyMode = .windows
    public var terminalApp = "terminal"
    public var terminalFollow = true
    public var columns: [ColumnState] = []
    public var windows: [WindowState] = []
    public var collapsedSidebarSections: [String] = []
    /// Network drives in the sidebar. Their passwords are in the Keychain, never here.
    public var networkDrives: [NetworkDrive] = []
    /// ⌥⌘Space opens a new window from any app. While it is on, Luksfer keeps running without a window.
    public var newWindowHotKey = true

    public init() {}

    public static func defaults(home: URL) -> AppSettings {
        var s = AppSettings()
        s.favorites = [
            Favorite(path: home.path, label: home.lastPathComponent),
            Favorite(path: home.appendingPathComponent("Downloads").path, label: "Downloads"),
            Favorite(path: home.appendingPathComponent("Documents").path, label: "Documents"),
        ]
        return s
    }

    // Decode missing keys with defaults, so older settings files keep working.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try c.decodeIfPresent([Favorite].self, forKey: .favorites) ?? []
        showHidden = try c.decodeIfPresent(Bool.self, forKey: .showHidden) ?? false
        keyMode = try c.decodeIfPresent(KeyMode.self, forKey: .keyMode) ?? .windows
        terminalApp = try c.decodeIfPresent(String.self, forKey: .terminalApp) ?? "terminal"
        terminalFollow = try c.decodeIfPresent(Bool.self, forKey: .terminalFollow) ?? true
        columns = try c.decodeIfPresent([ColumnState].self, forKey: .columns) ?? []
        windows = try c.decodeIfPresent([WindowState].self, forKey: .windows) ?? []
        collapsedSidebarSections = try c.decodeIfPresent([String].self, forKey: .collapsedSidebarSections) ?? []
        networkDrives = try c.decodeIfPresent([NetworkDrive].self, forKey: .networkDrives) ?? []
        newWindowHotKey = try c.decodeIfPresent(Bool.self, forKey: .newWindowHotKey) ?? true
    }
}

/// Loads and saves `AppSettings` as JSON. Luksfer never writes settings anywhere else.
public final class SettingsStore {
    public let fileURL: URL
    public private(set) var settings: AppSettings
    private var saveScheduled = false

    public static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Luksfer", isDirectory: true)
    }

    /// The settings folder of the app's working name, Okno (before it was renamed to Luksfer).
    public static var oldFolder: URL {
        defaultFolder.deletingLastPathComponent().appendingPathComponent("Okno", isDirectory: true)
    }

    /// Copies `settings.json` from `old` to `new` when `new` has none yet. The old file stays
    /// where it is. Returns whether it copied.
    @discardableResult
    public static func copyOldSettings(from old: URL = oldFolder, to new: URL = defaultFolder) -> Bool {
        let fm = FileManager.default
        let source = old.appendingPathComponent("settings.json"), target = new.appendingPathComponent("settings.json")
        guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path) else { return false }
        do {
            try fm.createDirectory(at: new, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: target)
            return true
        } catch {
            return false
        }
    }

    public init(folder: URL = SettingsStore.defaultFolder, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        fileURL = folder.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loaded
        } else {
            settings = .defaults(home: home)
        }
    }

    /// Changes the settings and saves them a moment later (changes in a burst are saved once).
    public func update(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        settings = copy
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.saveScheduled = false
            self?.saveNow()
        }
    }

    public func saveNow() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Luksfer: could not save settings: \(error.localizedDescription)")
        }
    }
}
