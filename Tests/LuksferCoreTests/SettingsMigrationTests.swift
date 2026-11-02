import XCTest
@testable import LuksferCore

final class SettingsMigrationTests: XCTestCase {
    func testCopiesOldSettingsAndKeepsThem() throws {
        let box = CoreSandbox()
        let old = box.folder("Okno"), new = box.root.appendingPathComponent("Luksfer", isDirectory: true)
        box.file("Okno/settings.json", #"{"showHidden":true}"#)
        XCTAssertTrue(SettingsStore.copyOldSettings(from: old, to: new))
        XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("settings.json"), encoding: .utf8), #"{"showHidden":true}"#)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("settings.json").path), "the old file stays")
        XCTAssertTrue(SettingsStore(folder: new).settings.showHidden)
    }

    func testNeverOverwritesNewSettings() throws {
        let box = CoreSandbox()
        box.file("Okno/settings.json", #"{"showHidden":true}"#)
        box.file("Luksfer/settings.json", #"{"showHidden":false}"#)
        XCTAssertFalse(SettingsStore.copyOldSettings(from: box.root.appendingPathComponent("Okno"), to: box.root.appendingPathComponent("Luksfer")))
        XCTAssertEqual(try String(contentsOf: box.root.appendingPathComponent("Luksfer/settings.json"), encoding: .utf8), #"{"showHidden":false}"#)
    }

    func testOlderSettingsTurnTheNewWindowKeyOn() {
        let box = CoreSandbox()
        box.file("Luksfer/settings.json", #"{"showHidden":true}"#)
        XCTAssertTrue(SettingsStore(folder: box.root.appendingPathComponent("Luksfer")).settings.newWindowHotKey)
        box.file("Luksfer/settings.json", #"{"newWindowHotKey":false}"#)
        XCTAssertFalse(SettingsStore(folder: box.root.appendingPathComponent("Luksfer")).settings.newWindowHotKey)
    }

    func testSavedFileAndFolderArePrivate() throws {
        let box = CoreSandbox()
        func mode(_ url: URL) throws -> Int {
            try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
        }
        let fresh = SettingsStore(folder: box.root.appendingPathComponent("New"), home: box.root)
        fresh.saveNow()
        XCTAssertEqual(try mode(fresh.fileURL), 0o600)
        XCTAssertEqual(try mode(fresh.fileURL.deletingLastPathComponent()), 0o700)

        // A file and folder from an older version get private at the next save.
        let oldFile = box.file("Old/settings.json", #"{"showHidden":true}"#), oldFolder = box.root.appendingPathComponent("Old")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: oldFile.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldFolder.path)
        SettingsStore(folder: oldFolder, home: box.root).saveNow()
        XCTAssertEqual(try mode(oldFile), 0o600)
        XCTAssertEqual(try mode(oldFolder), 0o700)
        XCTAssertTrue(SettingsStore(folder: oldFolder, home: box.root).settings.showHidden, "the settings stay")
    }

    func testNothingToCopy() {
        let box = CoreSandbox()
        XCTAssertFalse(SettingsStore.copyOldSettings(from: box.root.appendingPathComponent("Okno"), to: box.root.appendingPathComponent("Luksfer")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: box.root.appendingPathComponent("Luksfer").path))
    }
}
