import Darwin
import XCTest
@testable import OknoCore

/// A folder tree made by a test under ~/Library/Caches/okno-dev/sandbox/pathbar/, removed after.
struct PathSandbox {
    let root: URL

    init() throws {
        let caches = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        root = caches.appendingPathComponent("okno-dev/sandbox/pathbar/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func file(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative, isDirectory: false)
        try Data("test".utf8).write(to: url)
        return url
    }

    func remove() {
        precondition(root.path.contains("/okno-dev/sandbox/pathbar/"))
        try? FileManager.default.removeItem(at: root)
    }
}

final class PathCompleterTests: XCTestCase {
    private var sandbox: PathSandbox!
    private var root: String { sandbox.root.path }

    override func setUpWithError() throws {
        sandbox = try PathSandbox()
        for name in ["Alpha", "Album", "Beta", ".cache", "Tool.app", "Secret", "Version 1.2"] {
            try sandbox.folder(name)
        }
        try sandbox.file("alpha.txt")
        try sandbox.file("Bravo.txt")
        XCTAssertEqual(chflags(sandbox.root.appendingPathComponent("Secret").path, UInt32(UF_HIDDEN)), 0)
        symlink(sandbox.root.appendingPathComponent("Beta").path, sandbox.root.appendingPathComponent("Link").path)
    }

    override func tearDown() {
        sandbox.remove()
    }

    private func names(_ text: String, base: URL? = nil, limit: Int = 12) -> [String] {
        PathCompleter.suggestions(for: text, relativeTo: base ?? sandbox.root, limit: limit, home: sandbox.root)
            .map(\.lastPathComponent)
    }

    func testSuggestionsListFoldersInFinderOrder() {
        XCTAssertEqual(names(root + "/"), ["Album", "Alpha", "Beta", "Link", "Version 1.2"])
    }

    func testSuggestionsMatchThePrefixInAnyCase() {
        XCTAssertEqual(names(root + "/Al"), ["Album", "Alpha"])
        XCTAssertEqual(names(root + "/al"), ["Album", "Alpha"])
        XCTAssertEqual(names(root + "/b"), ["Beta"])
        XCTAssertEqual(names(root + "/x"), [])
    }

    func testSuggestionsReturnFolderURLs() {
        let urls = PathCompleter.suggestions(for: root + "/Be", relativeTo: sandbox.root, home: sandbox.root)
        XCTAssertEqual(urls.map(\.path), [root + "/Beta"])
        XCTAssertTrue(urls[0].hasDirectoryPath)
    }

    func testDotFoldersOnlyWhenTheTypedPartStartsWithADot() {
        XCTAssertFalse(names(root + "/").contains(".cache"))
        XCTAssertEqual(names(root + "/."), [".cache"])
        XCTAssertEqual(names(root + "/.ca"), [".cache"])
    }

    func testFlaggedHiddenFoldersOnlyWhenALetterIsTyped() {
        XCTAssertFalse(names(root + "/").contains("Secret"))
        XCTAssertEqual(names(root + "/se"), ["Secret"])
    }

    func testPackagesAreNotFolders() {
        XCTAssertEqual(names(root + "/T"), [])
        XCTAssertTrue(Subfolders.isPackage(name: "Tool.app"))
        XCTAssertFalse(Subfolders.isPackage(name: "Version 1.2"))
        XCTAssertFalse(Subfolders.isPackage(name: "Alpha"))
    }

    func testSuggestionsForRelativeTildeAndQuotedText() throws {
        try sandbox.folder("Beta/Inner")
        XCTAssertEqual(names("Be"), ["Beta"])
        XCTAssertEqual(names("~/Be"), ["Beta"])
        XCTAssertEqual(names("Beta/"), ["Inner"])
        XCTAssertEqual(names("'" + root + "/Ve"), ["Version 1.2"])
        XCTAssertEqual(names(root + "/Version\\ 1"), ["Version 1.2"])
        XCTAssertEqual(names(""), [])
    }

    func testSuggestionsStopAtTheLimit() throws {
        for number in 1...15 { try sandbox.folder("Many/Item \(number)") }
        let found = names(root + "/Many/", limit: 12)
        XCTAssertEqual(found.count, 12)
        XCTAssertEqual(Array(found.prefix(3)), ["Item 1", "Item 2", "Item 3"])
        XCTAssertEqual(found.last, "Item 12")
    }

    func testCompleteSingleMatchAddsASlash() {
        XCTAssertEqual(PathCompleter.complete(root + "/Be", relativeTo: sandbox.root), root + "/Beta/")
        XCTAssertEqual(PathCompleter.complete(root + "/ver", relativeTo: sandbox.root), root + "/Version 1.2/")
    }

    func testCompleteSeveralMatchesGivesTheCommonPrefix() {
        XCTAssertEqual(PathCompleter.complete(root + "/A", relativeTo: sandbox.root), root + "/Al")
        XCTAssertEqual(PathCompleter.complete(root + "/al", relativeTo: sandbox.root), root + "/Al")
        XCTAssertNil(PathCompleter.complete(root + "/Al", relativeTo: sandbox.root))
    }

    func testCompleteKeepsTheTypedForm() {
        XCTAssertEqual(PathCompleter.complete("~/Be", relativeTo: sandbox.root, home: sandbox.root), "~/Beta/")
        XCTAssertEqual(PathCompleter.complete("Be", relativeTo: sandbox.root), "Beta/")
        XCTAssertEqual(PathCompleter.complete("'" + root + "/Ve'", relativeTo: sandbox.root), "'" + root + "/Version 1.2/")
        XCTAssertEqual(PathCompleter.complete("~", relativeTo: sandbox.root), "~/")
    }

    func testTextForAChosenSuggestionKeepsTheTypedForm() {
        XCTAssertEqual(PathCompleter.text("~/Pro", choosing: "Projects"), "~/Projects/")
        XCTAssertEqual(PathCompleter.text("~/", choosing: "Projects"), "~/Projects/")
        XCTAssertEqual(PathCompleter.text("~", choosing: "Projects"), "~/Projects/")
        XCTAssertEqual(PathCompleter.text("Pro", choosing: "Projects"), "Projects/")
        XCTAssertEqual(PathCompleter.text("/Users/alex/My\\ F", choosing: "My Folder"), "/Users/alex/My Folder/")
        XCTAssertEqual(PathCompleter.text("'/Users/alex/My F'", choosing: "My Folder"), "'/Users/alex/My Folder/")
        XCTAssertEqual(PathCompleter.text("/a/", choosing: "back\\slash"), "/a/back\\\\slash/")
    }

    func testCompleteFindsNothing() {
        XCTAssertNil(PathCompleter.complete(root + "/Zulu", relativeTo: sandbox.root))
        XCTAssertNil(PathCompleter.complete(root + "/To", relativeTo: sandbox.root))
        XCTAssertNil(PathCompleter.complete(root + "/Bra", relativeTo: sandbox.root))
    }

    func testSubfolderListForMenus() {
        XCTAssertEqual(Subfolders.list(in: sandbox.root).map(\.lastPathComponent),
                       ["Album", "Alpha", "Beta", "Link", "Version 1.2"])
        XCTAssertEqual(Subfolders.list(in: sandbox.root, includeHidden: true).map(\.lastPathComponent),
                       [".cache", "Album", "Alpha", "Beta", "Link", "Secret", "Version 1.2"])
        XCTAssertEqual(Subfolders.list(in: sandbox.root.appendingPathComponent("Missing")), [])
    }
}
