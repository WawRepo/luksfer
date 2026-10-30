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

    func testSortPutsFoldersFirstAndUsesFinderOrder() throws {
        let box = CoreSandbox()
        for n in ["file 10.txt", "file 2.txt", "B.txt", "a.txt"] { box.file(n) }
        box.folder("zeta")
        box.folder("Alpha")
        let items = try DirectoryReader.read(box.root, includeHidden: false)
        let names = FileSorter.sort(items, by: FileSortOrder(key: .name, ascending: true)).map(\.name)
        XCTAssertEqual(names, ["Alpha", "zeta", "a.txt", "B.txt", "file 2.txt", "file 10.txt"])
        let down = FileSorter.sort(items, by: FileSortOrder(key: .name, ascending: false)).map(\.name)
        XCTAssertEqual(down, ["zeta", "Alpha", "file 10.txt", "file 2.txt", "B.txt", "a.txt"])
    }

    func testSortBySizeKeepsFoldersFirst() throws {
        let box = CoreSandbox()
        box.file("big.txt", String(repeating: "x", count: 100))
        box.file("small.txt", "x")
        box.folder("dir")
        let items = try DirectoryReader.read(box.root, includeHidden: false)
        XCTAssertEqual(FileSorter.sort(items, by: FileSortOrder(key: .size, ascending: false)).map(\.name), ["dir", "big.txt", "small.txt"])
        XCTAssertEqual(FileSorter.sort(items, by: FileSortOrder(key: .size, ascending: true)).map(\.name), ["dir", "small.txt", "big.txt"])
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
