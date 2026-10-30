import XCTest
@testable import OknoCore

/// New folder, new file, Move to Trash and permanent delete.
final class FileOperationCreateTests: FileOperationTestCase {
    // MARK: New items

    func testNewFolderNamesCountUp() throws {
        let first = try engine.createFolder(in: root)
        let second = try engine.createFolder(in: root)
        let third = try engine.createFolder(in: root)
        XCTAssertEqual(try names(), ["New folder", "New folder (2)", "New folder (3)"])
        XCTAssertEqual(first.actionName, "New Folder")
        XCTAssertEqual(third.createdItems.map(\.path), [url("New folder (3)").path])
        XCTAssertTrue(second.createdItems[0].hasDirectoryPath)
        XCTAssertEqual(try snapshot()["New folder (2)"], .folder)
    }

    func testNewFileWithContents() throws {
        let change = try engine.createFile(in: root, named: "notes.md", contents: Data("# Hi".utf8))
        _ = try engine.createFile(in: root, named: "notes.md")
        _ = try engine.createFile(in: root)
        XCTAssertEqual(try names(), ["New text file.txt", "notes (2).md", "notes.md"])
        XCTAssertEqual(try text(url("notes.md")), "# Hi")
        XCTAssertEqual(try text(url("notes (2).md")), "")
        XCTAssertEqual(change.actionName, "New File")
        XCTAssertEqual(change.createdItems.map(\.path), [url("notes.md").path])
    }

    func testNewItemWithInvalidName() async throws {
        let error = await operationError { _ = try self.engine.createFolder(in: self.root, named: "a/b") }
        guard case .invalidName = error else { return XCTFail("\(String(describing: error))") }
        let fileError = await operationError { _ = try self.engine.createFile(in: self.root, named: "..") }
        guard case .invalidName = fileError else { return XCTFail("\(String(describing: fileError))") }
        XCTAssertEqual(try names(), [])
    }

    func testNewItemInMissingFolder() async {
        let error = await operationError { _ = try self.engine.createFile(in: self.url("gone", isFolder: true)) }
        guard case .sourceMissing("gone") = error else { return XCTFail("\(String(describing: error))") }
    }

    func testUndoNewFileMovesItToTrash() async throws {
        let change = try engine.createFile(in: root, named: "draft.txt", contents: Data("keep me".utf8))
        let redo = try await engine.undo(change)
        XCTAssertEqual(try names(), [])
        XCTAssertEqual(try trashNames(), ["draft.txt"], "undo trashes, never deletes")
        XCTAssertEqual(try text(trashFolder.appendingPathComponent("draft.txt")), "keep me")
        XCTAssertEqual(redo.actionName, "New File")
        _ = try await engine.undo(redo)
        XCTAssertEqual(try text(url("draft.txt")), "keep me")
        XCTAssertEqual(try trashNames(), [])
    }

    // MARK: Trash

    func testTrashAndUndo() async throws {
        let a = try file("a.txt", "a")
        try file("b.txt", "b")
        try file("f/child.txt", "c")
        let f = url("f", isFolder: true)
        let change = try await engine.trash([a, f, url("f/child.txt")])
        XCTAssertEqual(try names(), ["b.txt"])
        XCTAssertEqual(try trashNames(), ["a.txt", "f"], "the child goes with its folder, once")
        XCTAssertEqual(change.actionName, "Move to Trash")
        XCTAssertEqual(change.createdItems, [])
        XCTAssertTrue(change.touchedFolders.contains(URL(fileURLWithPath: root.path, isDirectory: true)))

        let redo = try await engine.undo(change)
        XCTAssertEqual(try snapshot(), [
            "a.txt": .file(Data("a".utf8)), "b.txt": .file(Data("b".utf8)),
            "f": .folder, "f/child.txt": .file(Data("c".utf8)),
        ])
        XCTAssertEqual(Set(redo.createdItems.map(\.lastPathComponent)), ["a.txt", "f"])
        XCTAssertEqual(try trashNames(), [])
    }

    func testTrashMissingItemChangesNothing() async throws {
        let a = try file("a.txt")
        let error = await operationError { _ = try await self.engine.trash([a, self.url("gone.txt")]) }
        guard case .sourceMissing("gone.txt") = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(try names(), ["a.txt"])
        XCTAssertEqual(try trashNames(), [])
    }

    func testUndoTrashWhenNameIsTakenAgain() async throws {
        let a = try file("a.txt", "old")
        let change = try await engine.trash([a])
        try file("a.txt", "new")
        let redo = try await engine.undo(change)
        XCTAssertEqual(try names(), ["a (2).txt", "a.txt"])
        XCTAssertEqual(try text(url("a.txt")), "new")
        XCTAssertEqual(try text(url("a (2).txt")), "old")
        XCTAssertEqual(redo.createdItems.map(\.lastPathComponent), ["a (2).txt"])
    }

    func testUndoTrashRemakesMissingFolder() async throws {
        let a = try file("f/a.txt", "a")
        let change = try await engine.trash([a])
        try fm.removeItem(at: url("f", isFolder: true))
        _ = try await engine.undo(change)
        XCTAssertEqual(try text(url("f/a.txt")), "a")
    }

    // MARK: Permanent delete

    func testDeletePermanently() async throws {
        let a = try file("a.txt")
        try file("f/inner.txt")
        try await engine.deletePermanently([a, url("f", isFolder: true), url("gone.txt")])
        XCTAssertEqual(try names(), [])
        XCTAssertEqual(try trashNames(), [], "a permanent delete skips the Trash")
    }
}
