import XCTest
import UniformTypeIdentifiers
@testable import LuksferCore

final class ListingTests: XCTestCase {
    func testReaderReadsNamesKindsAndSizes() throws {
        let box = CoreSandbox()
        box.file("notes.md", "hello")
        box.file(".secret", "x")
        box.folder("Projects")
        box.folder("Tool.app/Contents")
        try FileManager.default.createSymbolicLink(at: box.root.appendingPathComponent("link"),
                                                   withDestinationURL: box.root.appendingPathComponent("Projects"))

        let items = try DirectoryReader.read(box.root, includeHidden: false)
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        XCTAssertEqual(Set(byName.keys), ["notes.md", "Projects", "Tool.app", "link"])
        XCTAssertEqual(byName["notes.md"]?.size, 5)
        XCTAssertEqual(byName["notes.md"]?.isFolder, false)
        XCTAssertEqual(byName["notes.md"]?.type.conforms(to: .text), true)
        XCTAssertEqual(byName["Projects"]?.isFolder, true)
        XCTAssertEqual(byName["Tool.app"]?.isFolder, false)
        XCTAssertEqual(byName["Tool.app"]?.isPackage, true)
        XCTAssertEqual(byName["link"]?.isSymlink, true)
        XCTAssertEqual(byName["link"]?.isFolder, true)
        XCTAssertEqual(byName["notes.md"]?.isCloudOnly, false)

        let all = try DirectoryReader.read(box.root, includeHidden: true)
        XCTAssertTrue(all.contains { $0.name == ".secret" && $0.isHidden })
    }

    func testReaderThrowsForMissingFolder() {
        let box = CoreSandbox()
        XCTAssertThrowsError(try DirectoryReader.read(box.root.appendingPathComponent("nope"), includeHidden: false))
    }

    func testFoldersFirstPutsFoldersFirstAscendingAndLastDescending() throws {
        let box = CoreSandbox()
        for n in ["file 10.txt", "file 2.txt", "B.txt", "a.txt"] { box.file(n) }
        box.folder("zeta")
        box.folder("Alpha")
        let items = try DirectoryReader.read(box.root, includeHidden: false)
        let names = FileSorter.sort(items, by: FileSortOrder(key: .name, ascending: true), foldersFirst: true).map(\.name)
        XCTAssertEqual(names, ["Alpha", "zeta", "a.txt", "B.txt", "file 2.txt", "file 10.txt"])
        let down = FileSorter.sort(items, by: FileSortOrder(key: .name, ascending: false), foldersFirst: true).map(\.name)
        XCTAssertEqual(down, ["file 10.txt", "file 2.txt", "B.txt", "a.txt", "zeta", "Alpha"])
    }

    func testFoldersAndFilesSortTogetherByName() throws {
        let box = CoreSandbox()
        for n in ["file 10.txt", "file 2.txt", "B.txt", "a.txt"] { box.file(n) }
        box.folder("zeta")
        box.folder("Alpha")
        box.folder("file 3")
        let items = try DirectoryReader.read(box.root, includeHidden: false)
        let names = FileSorter.sort(items, by: FileSortOrder(key: .name, ascending: true), foldersFirst: false).map(\.name)
        XCTAssertEqual(names, ["a.txt", "Alpha", "B.txt", "file 2.txt", "file 3", "file 10.txt", "zeta"])
        let down = FileSorter.sort(items, by: FileSortOrder(key: .name, ascending: false), foldersFirst: false).map(\.name)
        XCTAssertEqual(down, Array(names.reversed()))
    }

    /// Downloads newest first: a folder that came in after a file is above it, and an older folder
    /// below it. Equal dates go by name.
    func testFoldersAndFilesSortTogetherByDate() throws {
        let box = CoreSandbox()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let dated: [(String, Bool, TimeInterval)] = [("old.zip", false, 0), ("old folder", true, 10), ("mid.pdf", false, 20),
                                                       ("new folder", true, 30), ("new.dmg", false, 40), ("same b.txt", false, 50),
                                                       ("same a", true, 50)]
        for (name, isFolder, offset) in dated {
            let url = isFolder ? box.folder(name) : box.file(name)
            try FileManager.default.setAttributes([.modificationDate: base.addingTimeInterval(offset)], ofItemAtPath: url.path)
        }
        let items = try DirectoryReader.read(box.root, includeHidden: false)
        let newest = FileSorter.sort(items, by: FileSortOrder(key: .modified, ascending: false), foldersFirst: false).map(\.name)
        XCTAssertEqual(newest, ["same b.txt", "same a", "new.dmg", "new folder", "mid.pdf", "old folder", "old.zip"])
        let oldest = FileSorter.sort(items, by: FileSortOrder(key: .modified, ascending: true), foldersFirst: false).map(\.name)
        XCTAssertEqual(oldest, ["old.zip", "old folder", "mid.pdf", "new folder", "new.dmg", "same a", "same b.txt"])
        let grouped = FileSorter.sort(items, by: FileSortOrder(key: .modified, ascending: false), foldersFirst: true).map(\.name)
        XCTAssertEqual(grouped, ["same b.txt", "new.dmg", "mid.pdf", "old.zip", "same a", "new folder", "old folder"])
    }

    func testNewWindowSortsDownloadsNewestFirst() {
        let downloads = URL(fileURLWithPath: "/w/home/Downloads", isDirectory: true)
        XCTAssertEqual(FileSortOrder.newWindow(in: URL(fileURLWithPath: "/w/home/Downloads/", isDirectory: true), downloads: downloads),
                       FileSortOrder(key: .modified, ascending: false))
        XCTAssertEqual(FileSortOrder.newWindow(in: URL(fileURLWithPath: "/w/home/Documents", isDirectory: true), downloads: downloads),
                       FileSortOrder(key: .name, ascending: true))
        XCTAssertEqual(FileSortOrder.newWindow(in: URL(fileURLWithPath: "/w/home/Downloads/sub", isDirectory: true), downloads: downloads),
                       FileSortOrder(key: .name, ascending: true))
    }

    func testSortBySizeTurnsFoldersAroundToo() throws {
        let box = CoreSandbox()
        box.file("big.txt", String(repeating: "x", count: 100))
        box.file("small.txt", "x")
        box.folder("dir")
        let items = try DirectoryReader.read(box.root, includeHidden: false)
        // A folder has no size, so a sort by size keeps folders apart even when they sort with files.
        for foldersFirst in [true, false] {
            XCTAssertEqual(FileSorter.sort(items, by: FileSortOrder(key: .size, ascending: false), foldersFirst: foldersFirst).map(\.name), ["big.txt", "small.txt", "dir"])
            XCTAssertEqual(FileSorter.sort(items, by: FileSortOrder(key: .size, ascending: true), foldersFirst: foldersFirst).map(\.name), ["dir", "small.txt", "big.txt"])
        }
    }

    func testTypeNames() throws {
        let box = CoreSandbox()
        box.folder("dir")
        box.file("noext")
        box.file("data.weirdext")
        let items = try DirectoryReader.read(box.root, includeHidden: false)
        let names = Dictionary(uniqueKeysWithValues: items.map { ($0.name, FileTypes.displayName(for: $0)) })
        XCTAssertEqual(names["dir"], "Folder")
        XCTAssertEqual(names["noext"], "Document")
        XCTAssertEqual(names["data.weirdext"], "WEIRDEXT file")
    }

    func testTypeNamesAreExplorerStyle() throws {
        let box = CoreSandbox()
        for n in ["notes.txt", "app.ts", "Report.PDF", ".gitignore", "Makefile", "page.rtf"] { box.file(n) }
        let items = try DirectoryReader.read(box.root, includeHidden: true)
        let names = Dictionary(uniqueKeysWithValues: items.map { ($0.name, FileTypes.displayName(for: $0)) })
        XCTAssertEqual(names["notes.txt"], "Text document")
        XCTAssertEqual(names["app.ts"], "TypeScript file")
        XCTAssertEqual(names["Report.PDF"], "PDF document")
        XCTAssertEqual(names[".gitignore"], "Git ignore file")
        XCTAssertEqual(names["Makefile"], "Makefile")
        let rtf = try XCTUnwrap(names["page.rtf"])
        XCTAssertEqual(rtf.first.map(String.init), rtf.first.map { String($0).uppercased() }, "system names start with a capital")
    }

    func testFilterMatchesEveryWordAnyCase() throws {
        let box = CoreSandbox()
        for n in ["Report final.pdf", "report draft.pdf", "Café Zażółć.txt"] { box.file(n) }
        let items = try DirectoryReader.read(box.root, includeHidden: false)
        XCTAssertEqual(Set(ListFilter.filter(items, query: "REPORT final").map(\.name)), ["Report final.pdf"])
        XCTAssertEqual(ListFilter.filter(items, query: "cafe ZAŻÓŁĆ").map(\.name), ["Café Zażółć.txt"])
        XCTAssertEqual(ListFilter.filter(items, query: "  ").count, 3)
    }

    func testHistory() {
        let a = URL(fileURLWithPath: "/a"), b = URL(fileURLWithPath: "/b"), c = URL(fileURLWithPath: "/c")
        var h = NavigationHistory(start: a)
        h.visit(b)
        h.visit(c)
        XCTAssertEqual(h.goBack(), b)
        XCTAssertEqual(h.goBack(), a)
        XCTAssertNil(h.goBack())
        XCTAssertEqual(h.goForward(), b)
        h.visit(a)
        XCTAssertFalse(h.canGoForward)
        h.visit(a)
        XCTAssertEqual(h.backList, [b, a])
    }

    func testDropRule() {
        XCTAssertEqual(DropRule.operation(sameVolume: true, option: false, command: false), .move)
        XCTAssertEqual(DropRule.operation(sameVolume: false, option: false, command: false), .copy)
        XCTAssertEqual(DropRule.operation(sameVolume: true, option: true, command: false), .copy)
        XCTAssertEqual(DropRule.operation(sameVolume: false, option: false, command: true), .move)
        let box = CoreSandbox()
        XCTAssertTrue(DropRule.sameVolume(box.file("x"), box.folder("y")))
    }

    func testSettingsRoundTripAndDefaults() throws {
        let box = CoreSandbox()
        let home = box.folder("home")
        let store = SettingsStore(folder: box.root.appendingPathComponent("Luksfer"), home: home)
        XCTAssertEqual(store.settings.favorites.map(\.label), ["home", "Downloads", "Documents"])
        store.update { $0.showHidden = true; $0.favorites.removeLast() }
        store.saveNow()
        let again = SettingsStore(folder: box.root.appendingPathComponent("Luksfer"), home: home)
        XCTAssertTrue(again.settings.showHidden)
        XCTAssertEqual(again.settings.favorites.count, 2)
        // An old file without new keys still loads.
        try Data(#"{"showHidden": true}"#.utf8).write(to: again.fileURL)
        let old = SettingsStore(folder: box.root.appendingPathComponent("Luksfer"), home: home)
        XCTAssertTrue(old.settings.showHidden)
        XCTAssertEqual(old.settings.keyMode, .windows)
    }
}
