import XCTest
@testable import OknoCore

/// Move on one volume (rename) and across volumes (copy, then remove), clashes and guards.
final class FileOperationMoveTests: FileOperationTestCase {
    private func forceCrossVolume() {
        engine.isSameVolume = { _, _ in false }
    }

    func testSameVolumeMoveIsARename() async throws {
        let a = try file("src/a.txt", "a")
        try file("src/f/inner.txt", "i")
        let f = url("src/f", isFolder: true)
        let inodes = [inode(a), inode(f)]
        let dest = try folder("dest")
        let change = try await engine.move([a, f], into: dest, resolveClash: never, progress: nil)
        XCTAssertEqual(try names(url("src", isFolder: true)), [])
        XCTAssertEqual(try snapshot(dest), ["a.txt": .file(Data("a".utf8)), "f": .folder,
                                            "f/inner.txt": .file(Data("i".utf8))])
        XCTAssertEqual([inode(dest.appendingPathComponent("a.txt")), inode(dest.appendingPathComponent("f"))], inodes,
                       "same inode: renamed, not copied")
        XCTAssertEqual(change.actionName, "Move")
        XCTAssertEqual(change.createdItems.map(\.lastPathComponent), ["a.txt", "f"])
        XCTAssertEqual(change.touchedFolders, [FileChange.folderURL(dest), FileChange.folderURL(url("src", isFolder: true))])
    }

    func testCrossVolumeMoveCopiesThenRemovesTheOriginal() async throws {
        forceCrossVolume()
        engine.allowsCloning = false
        try file("src/f/inner.txt", "inner")
        try file("src/f/deep/d.txt", "deep")
        try link("src/f/link", to: "inner.txt")
        let f = url("src/f", isFolder: true)
        let before = try snapshot(f)
        let oldInode = inode(f)
        let dest = try folder("dest")
        let recorder = ProgressRecorder()
        let change = try await engine.move([f], into: dest, resolveClash: never, progress: recorder.handler)
        XCTAssertFalse(fm.fileExists(atPath: f.path), "the original is removed after the copy")
        XCTAssertEqual(try snapshot(dest.appendingPathComponent("f")), before)
        XCTAssertNotEqual(inode(dest.appendingPathComponent("f")), oldInode, "copied, not renamed")
        XCTAssertEqual(recorder.reports.last?.totalBytes, Int64("inner".utf8.count + "deep".utf8.count))
        XCTAssertEqual(recorder.reports.last?.completedBytes, recorder.reports.last?.totalBytes)
        XCTAssertEqual(change.createdItems.map(\.lastPathComponent), ["f"])
        XCTAssertEqual(try trashNames(), [])
    }

    func testMoveIntoItsOwnFolderDoesNothing() async throws {
        let a = try file("a.txt", "a")
        let change = try await engine.move([a], into: root, resolveClash: never, progress: nil)
        XCTAssertTrue(change.isEmpty)
        XCTAssertEqual(try names(), ["a.txt"])
    }

    func testMoveFolderIntoItself() async throws {
        let f = try folder("f")
        let sub = try folder("f/sub")
        for target in [f, sub] {
            let error = await operationError {
                _ = try await self.engine.move([f], into: target, resolveClash: self.never, progress: nil)
            }
            guard case .intoItself("f") = error else { return XCTFail("\(String(describing: error))") }
        }
        XCTAssertEqual(try snapshot(), ["f": .folder, "f/sub": .folder])
    }

    func testMovingAFolderAndItsChildMovesOnce() async throws {
        try file("f/child.txt", "c")
        let dest = try folder("dest")
        _ = try await engine.move([url("f", isFolder: true), url("f/child.txt")], into: dest,
                                  resolveClash: never, progress: nil)
        XCTAssertEqual(try snapshot(dest), ["f": .folder, "f/child.txt": .file(Data("c".utf8))])
    }

    func testMoveClashReplaceAndUndo() async throws {
        let source = try file("src/a.txt", "new")
        let dest = try folder("dest")
        try file("dest/a.txt", "old")
        let change = try await engine.move([source], into: dest, resolveClash: ClashRecorder(.replace).resolver,
                                           progress: nil)
        XCTAssertEqual(try text(dest.appendingPathComponent("a.txt")), "new")
        XCTAssertEqual(try names(url("src", isFolder: true)), [])
        XCTAssertEqual(try text(trashFolder.appendingPathComponent("a.txt")), "old")

        _ = try await engine.undo(change)
        XCTAssertEqual(try text(source), "new")
        XCTAssertEqual(try text(dest.appendingPathComponent("a.txt")), "old")
        XCTAssertEqual(try trashNames(), [])
    }

    func testMoveClashSkipAndKeepBoth() async throws {
        let one = try file("src/one.txt", "new1")
        let two = try file("other/two.txt", "new2")
        let dest = try folder("dest")
        try file("dest/one.txt", "old1")
        try file("dest/two.txt", "old2")
        _ = try await engine.move([one], into: dest, resolveClash: ClashRecorder(.skip).resolver, progress: nil)
        XCTAssertEqual(try text(one), "new1", "skipped: stays where it was")
        _ = try await engine.move([two], into: dest, resolveClash: ClashRecorder(.keepBoth).resolver, progress: nil)
        XCTAssertEqual(try text(dest.appendingPathComponent("two (2).txt")), "new2")
        XCTAssertEqual(try text(dest.appendingPathComponent("two.txt")), "old2")
    }

    func testReplaceRefusesToTrashTheFolderHoldingTheSource() async throws {
        // Moving "x/x" up into the folder that holds "x": replacing "x" would trash the source itself.
        let inner = try file("x/x", "inner")
        let error = await operationError {
            _ = try await self.engine.move([inner], into: self.root, resolveClash: ClashRecorder(.replace).resolver,
                                           progress: nil)
        }
        guard case .failed = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(try text(inner), "inner")
        XCTAssertEqual(try trashNames(), [])
    }

    func testMoveMissingDestinationFolder() async throws {
        let a = try file("a.txt")
        let error = await operationError {
            _ = try await self.engine.move([a], into: self.url("gone", isFolder: true), resolveClash: self.never,
                                           progress: nil)
        }
        guard case .sourceMissing("gone") = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(try names(), ["a.txt"])
    }
}
