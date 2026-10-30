import XCTest
@testable import LuksferCore

/// Unique names, name rules and rename.
final class FileOperationNamesTests: FileOperationTestCase {
    private func unique(_ name: String, _ style: UniqueNameStyle) -> String {
        FileOperationEngine.uniqueName(name, in: root, style: style)
    }

    // MARK: Unique names

    func testFreeNameStaysAsIs() {
        XCTAssertEqual(unique("a.txt", .numbered), "a.txt")
        XCTAssertEqual(unique("a.txt", .copy), "a.txt")
    }

    func testNumberedNames() throws {
        try file("a.txt")
        XCTAssertEqual(unique("a.txt", .numbered), "a (2).txt")
        try file("a (2).txt")
        XCTAssertEqual(unique("a.txt", .numbered), "a (3).txt")
        XCTAssertEqual(unique("a (2).txt", .numbered), "a (3).txt", "continues the count, no “a (2) (2)”")
        try folder("New folder")
        XCTAssertEqual(unique("New folder", .numbered), "New folder (2)")
    }

    func testCopyNames() throws {
        try file("a.txt")
        XCTAssertEqual(unique("a.txt", .copy), "a copy.txt")
        try file("a copy.txt")
        XCTAssertEqual(unique("a.txt", .copy), "a copy 2.txt")
        XCTAssertEqual(unique("a copy.txt", .copy), "a copy 2.txt", "continues the count, no “a copy copy”")
        try file("a copy 2.txt")
        XCTAssertEqual(unique("a copy 2.txt", .copy), "a copy 3.txt")
    }

    func testExtensionRules() throws {
        try folder("My.Project")
        XCTAssertEqual(unique("My.Project", .copy), "My.Project copy", "a plain folder has no extension")
        XCTAssertEqual(unique("My.Project", .numbered), "My.Project (2)")
        try folder("Tool.app")
        XCTAssertEqual(unique("Tool.app", .copy), "Tool copy.app", "a package keeps its extension")
        try file(".zshrc")
        XCTAssertEqual(unique(".zshrc", .copy), ".zshrc copy")
        try file("README")
        XCTAssertEqual(unique("README", .numbered), "README (2)")
        try file("v1.2 notes")
        XCTAssertEqual(unique("v1.2 notes", .numbered), "v1.2 notes (2)")
        try file("archive.tar.gz")
        XCTAssertEqual(unique("archive.tar.gz", .numbered), "archive.tar (2).gz")
    }

    func testOtherCaseCountsAsTakenOnCaseInsensitiveDisk() throws {
        try XCTSkipUnless(try isCaseInsensitiveVolume(), "the sandbox volume is case-sensitive")
        try file("a.txt")
        XCTAssertEqual(unique("A.txt", .numbered), "A (2).txt")
    }

    // MARK: Rename

    func testRename() throws {
        let item = try file("a.txt", "hello")
        let change = try engine.rename(item, to: "b.txt")
        XCTAssertEqual(try names(), ["b.txt"])
        XCTAssertEqual(try text(url("b.txt")), "hello")
        XCTAssertEqual(change.actionName, "Rename")
        XCTAssertEqual(change.createdItems.map(\.path), [url("b.txt").path])
        XCTAssertEqual(change.touchedFolders.map(\.path), [root.path])
    }

    func testRenameFolderKeepsContents() throws {
        try file("f/inner.txt", "x")
        _ = try engine.rename(url("f", isFolder: true), to: "g")
        XCTAssertEqual(try snapshot(), ["g": .folder, "g/inner.txt": .file(Data("x".utf8))])
    }

    func testCaseOnlyRename() async throws {
        let item = try file("a.txt", "hello")
        let before = inode(item)
        let change = try engine.rename(item, to: "A.txt")
        XCTAssertEqual(try names(), ["A.txt"])
        XCTAssertEqual(inode(url("A.txt")), before)
        _ = try await engine.undo(change)
        XCTAssertEqual(try names(), ["a.txt"])
        XCTAssertEqual(try text(url("a.txt")), "hello")
    }

    func testInvalidNames() async throws {
        let item = try file("a.txt")
        let tooLong = String(repeating: "é", count: 128)  // 256 UTF-8 bytes
        for name in ["", ".", "..", "a/b", "a\u{0}b", tooLong] {
            guard let error = await operationError({ _ = try self.engine.rename(item, to: name) }) else { continue }
            guard case .invalidName(let reported) = error else { return XCTFail("\(name): \(error)") }
            XCTAssertEqual(reported, name)
        }
        XCTAssertEqual(try names(), ["a.txt"])
        // 255 bytes is fine.
        _ = try engine.rename(item, to: String(repeating: "b", count: 255))
        XCTAssertEqual(try names(), [String(repeating: "b", count: 255)])
    }

    func testRenameToTakenName() async throws {
        let a = try file("a.txt", "a")
        try file("b.txt", "b")
        let error = await operationError { _ = try self.engine.rename(a, to: "b.txt") }
        guard case .nameTaken("b.txt") = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(try text(url("a.txt")), "a")
        XCTAssertEqual(try text(url("b.txt")), "b")
    }

    func testRenameToTakenNameInOtherCase() async throws {
        try XCTSkipUnless(try isCaseInsensitiveVolume(), "the sandbox volume is case-sensitive")
        let a = try file("a.txt", "a")
        try file("b.txt", "b")
        let error = await operationError { _ = try self.engine.rename(a, to: "B.txt") }
        guard case .nameTaken = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(try names(), ["a.txt", "b.txt"])
    }

    func testRenameMissingItem() async {
        let error = await operationError { _ = try self.engine.rename(self.url("gone.txt"), to: "b.txt") }
        guard case .sourceMissing("gone.txt") = error else { return XCTFail("\(String(describing: error))") }
    }

    func testRenameToSameNameDoesNothing() throws {
        let item = try file("a.txt")
        XCTAssertTrue(try engine.rename(item, to: "a.txt").isEmpty)
        XCTAssertEqual(try names(), ["a.txt"])
    }
}
