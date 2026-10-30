import XCTest
@testable import LuksferCore

/// Undo → redo → undo leaves the tree exactly as before, for every action; missing items on undo.
final class FileOperationUndoTests: FileOperationTestCase {
    private func makeTree() throws {
        try file("src/a.txt", "alpha")
        try file("src/dir/b.txt", "bravo")
        try link("src/dir/link", to: "b.txt")
        try folder("src/dir/empty")
        try folder("dest")
        try file("dest/a.txt", "old alpha")
    }

    private var src: URL { url("src", isFolder: true) }
    private var dest: URL { url("dest", isFolder: true) }

    func testRoundTripCopy() async throws {
        try makeTree()
        try await assertRoundTrip {
            try await engine.copy([url("src/dir", isFolder: true)], into: dest, resolveClash: never, progress: nil)
        }
    }

    func testRoundTripCopyIntoSameFolder() async throws {
        try makeTree()
        try await assertRoundTrip {
            try await engine.copy([url("src/a.txt"), url("src/dir", isFolder: true)], into: src,
                                  resolveClash: never, progress: nil)
        }
    }

    func testRoundTripCopyReplace() async throws {
        try makeTree()
        try await assertRoundTrip {
            try await engine.copy([url("src/a.txt")], into: dest, resolveClash: ClashRecorder(.replace).resolver,
                                  progress: nil)
        }
    }

    func testRoundTripCopyKeepBoth() async throws {
        try makeTree()
        try await assertRoundTrip {
            try await engine.copy([url("src/a.txt")], into: dest, resolveClash: ClashRecorder(.keepBoth).resolver,
                                  progress: nil)
        }
    }

    func testRoundTripMove() async throws {
        try makeTree()
        try await assertRoundTrip {
            try await engine.move([url("src/dir", isFolder: true)], into: dest, resolveClash: never, progress: nil)
        }
    }

    func testRoundTripMoveReplace() async throws {
        try makeTree()
        try await assertRoundTrip {
            try await engine.move([url("src/a.txt")], into: dest, resolveClash: ClashRecorder(.replace).resolver,
                                  progress: nil)
        }
    }

    func testRoundTripCrossVolumeMove() async throws {
        engine.isSameVolume = { _, _ in false }
        try makeTree()
        try await assertRoundTrip {
            try await engine.move([url("src/a.txt"), url("src/dir", isFolder: true)], into: dest,
                                  resolveClash: ClashRecorder(.replace).resolver, progress: nil)
        }
    }

    func testRoundTripDuplicate() async throws {
        try makeTree()
        try await assertRoundTrip {
            try await engine.duplicate([url("src/a.txt"), url("src/dir", isFolder: true)])
        }
    }

    func testRoundTripTrash() async throws {
        try makeTree()
        try await assertRoundTrip {
            try await engine.trash([url("src/a.txt"), url("src/dir", isFolder: true)])
        }
    }

    func testRoundTripRename() async throws {
        try makeTree()
        try await assertRoundTrip { try engine.rename(url("src/dir", isFolder: true), to: "renamed") }
    }

    func testRoundTripCaseOnlyRename() async throws {
        try makeTree()
        try await assertRoundTrip { try engine.rename(url("src/a.txt"), to: "A.txt") }
    }

    func testRoundTripNewFolder() async throws {
        try makeTree()
        try await assertRoundTrip { try engine.createFolder(in: src) }
    }

    func testRoundTripNewFile() async throws {
        try makeTree()
        try await assertRoundTrip { try engine.createFile(in: src, named: "note.md", contents: Data("hi".utf8)) }
    }

    // MARK: Missing items

    func testUndoPassesOverMissingItemsAndNamesThem() async throws {
        try file("src/a.txt", "a")
        try file("src/b.txt", "b")
        try folder("dest")
        let change = try await engine.copy([url("src/a.txt"), url("src/b.txt")], into: dest,
                                           resolveClash: never, progress: nil)
        try fm.removeItem(at: dest.appendingPathComponent("a.txt"))
        let error = await operationError { _ = try await self.engine.undo(change) }
        guard case .incomplete(let message, let partial) = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertTrue(message.contains("“a.txt”"), message)
        XCTAssertEqual(try names(dest), [], "the rest was undone")
        XCTAssertEqual(try trashNames(), ["b.txt"])
        XCTAssertEqual(partial.actionName, "Copy")
        _ = try await engine.undo(partial)
        XCTAssertEqual(try names(dest), ["b.txt"], "the partial redo works")
    }

    func testUndoWithEverythingMissing() async throws {
        let change = try engine.createFile(in: root, named: "a.txt")
        try fm.removeItem(at: url("a.txt"))
        let error = await operationError { _ = try await self.engine.undo(change) }
        guard case .sourceMissing("a.txt") = error else { return XCTFail("\(String(describing: error))") }
    }

    func testUndoTrashWhenItWasEmptied() async throws {
        let a = try file("a.txt")
        let b = try file("b.txt")
        let change = try await engine.trash([a, b])
        try fm.removeItem(at: trashFolder.appendingPathComponent("b.txt"))
        let error = await operationError { _ = try await self.engine.undo(change) }
        guard case .incomplete(let message, _) = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertTrue(message.contains("“b.txt”"), message)
        XCTAssertEqual(try names(), ["a.txt"])
    }

    func testUndoMoveWhenOriginalNameIsTaken() async throws {
        let a = try file("src/a.txt", "moved")
        try folder("dest")
        let change = try await engine.move([a], into: dest, resolveClash: never, progress: nil)
        try file("src/a.txt", "newcomer")
        _ = try await engine.undo(change)
        XCTAssertEqual(try text(url("src/a.txt")), "newcomer", "never overwritten")
        XCTAssertEqual(try text(url("src/a (2).txt")), "moved")
    }
}
