import XCTest
@testable import LuksferCore

/// Copy, duplicate, name clashes, progress and cancel.
final class FileOperationCopyTests: FileOperationTestCase {
    private func makeTree() throws {
        try file("src/a.txt", "alpha")
        try file("src/dir/b.txt", "bravo")
        try file("src/dir/sub/c.txt", "charlie")
        try link("src/dir/link", to: "b.txt")
        try folder("src/dir/empty")
    }

    // MARK: Copy

    func testCopyFilesAndFolderTree() async throws {
        try makeTree()
        let dest = try folder("dest")
        let sourceBefore = try snapshot(url("src", isFolder: true))
        let change = try await engine.copy([url("src/a.txt"), url("src/dir", isFolder: true)], into: dest,
                                           resolveClash: never, progress: nil)
        XCTAssertEqual(try snapshot(dest), sourceBefore, "same names, kinds, contents and links")
        XCTAssertEqual(try snapshot(url("src", isFolder: true)), sourceBefore, "the source is untouched")
        XCTAssertEqual(try snapshot(dest)["dir/link"], .link("b.txt"), "a link stays a link")
        XCTAssertEqual(change.actionName, "Copy")
        XCTAssertEqual(change.createdItems.map(\.path), [dest.appendingPathComponent("a.txt").path,
                                                         dest.appendingPathComponent("dir").path])
        XCTAssertEqual(change.touchedFolders, [FileChange.folderURL(dest)])
    }

    func testCopyWithoutCloningCopiesBytes() async throws {
        engine.allowsCloning = false
        try makeTree()
        let dest = try folder("dest")
        _ = try await engine.copy([url("src/dir", isFolder: true)], into: dest, resolveClash: never, progress: nil)
        XCTAssertEqual(try snapshot(dest.appendingPathComponent("dir")), try snapshot(url("src/dir", isFolder: true)))
    }

    func testTopLevelLinkStaysALink() async throws {
        try folder("src/target")
        let item = try link("src/shortcut", to: "target")
        let dest = try folder("dest")
        _ = try await engine.copy([item], into: dest, resolveClash: never, progress: nil)
        engine.isSameVolume = { _, _ in false }
        let other = try folder("other")
        _ = try await engine.move([item], into: other, resolveClash: never, progress: nil)
        XCTAssertEqual(try snapshot(dest), ["shortcut": .link("target")])
        XCTAssertEqual(try snapshot(other), ["shortcut": .link("target")])
        XCTAssertEqual(try names(url("src", isFolder: true)), ["target"])
    }

    func testFailedCopyStopsAndKeepsDoneItemsUndoable() async throws {
        let ok = try file("src/ok.txt", "ok")
        let locked = try file("src/dir/locked.txt", "secret")
        try file("src/dir/fine.txt", "fine")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        let dest = try folder("dest")
        let error = await operationError {
            _ = try await self.engine.copy([ok, self.url("src/dir", isFolder: true), self.url("src/ok.txt")],
                                           into: dest, resolveClash: self.never, progress: nil)
        }
        guard case .incomplete(let message, let partial) = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertTrue(message.contains("locked.txt"), message)
        XCTAssertEqual(partial.createdItems.map(\.lastPathComponent), ["ok.txt"])
        XCTAssertEqual(try names(dest), ["ok.txt"], "no half-copied folder, no temporary item")
        _ = try await engine.undo(partial)
        XCTAssertEqual(try names(dest), [])
    }

    func testCopyIntoSameFolderMakesCopyNames() async throws {
        let a = try file("a.txt", "a")
        let f = try folder("f")
        try file("f/inner.txt", "i")
        _ = try await engine.copy([a, f], into: root, resolveClash: never, progress: nil)
        let second = try await engine.copy([a], into: root, resolveClash: never, progress: nil)
        XCTAssertEqual(try names(), ["a copy 2.txt", "a copy.txt", "a.txt", "f", "f copy"])
        XCTAssertEqual(try text(url("a copy 2.txt")), "a")
        XCTAssertEqual(try text(url("f copy/inner.txt")), "i")
        XCTAssertEqual(second.createdItems.map(\.lastPathComponent), ["a copy 2.txt"])
    }

    func testDuplicateNames() async throws {
        let a = try file("a.txt", "a")
        let f = try folder("f")
        try file("f/inner.txt", "i")
        let change = try await engine.duplicate([a, f])
        _ = try await engine.duplicate([a])
        XCTAssertEqual(try names(), ["a copy 2.txt", "a copy.txt", "a.txt", "f", "f copy"])
        XCTAssertEqual(try text(url("f copy/inner.txt")), "i")
        XCTAssertEqual(change.actionName, "Duplicate")
        XCTAssertEqual(change.createdItems.map(\.lastPathComponent), ["a copy.txt", "f copy"])
    }

    func testCopyFolderIntoItself() async throws {
        let f = try folder("f")
        let sub = try folder("f/sub")
        for target in [f, sub] {
            let error = await operationError {
                _ = try await self.engine.copy([f], into: target, resolveClash: self.never, progress: nil)
            }
            guard case .intoItself("f") = error else { return XCTFail("\(String(describing: error))") }
        }
        XCTAssertEqual(try snapshot(), ["f": .folder, "f/sub": .folder])
    }

    func testCopyMissingSourceChangesNothing() async throws {
        let a = try file("a.txt")
        let dest = try folder("dest")
        let error = await operationError {
            _ = try await self.engine.copy([a, self.url("gone.txt")], into: dest, resolveClash: self.never, progress: nil)
        }
        guard case .sourceMissing("gone.txt") = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(try names(dest), [])
    }

    func testCopyRunsOffTheMainThread() async throws {
        try makeTree()
        let dest = try folder("dest")
        let recorder = ProgressRecorder()
        let engine = self.engine!
        let items = [url("src", isFolder: true)]
        let never = self.never
        let isMain = await MainActor.run { Thread.isMainThread }
        XCTAssertTrue(isMain)
        _ = try await Task { @MainActor in
            try await engine.copy(items, into: dest, resolveClash: never, progress: recorder.handler)
        }.value
        XCTAssertFalse(recorder.reports.isEmpty)
        XCTAssertFalse(recorder.anyOnMainThread, "file work and progress run off the main thread")
    }

    // MARK: Clashes

    func testClashSkip() async throws {
        let source = try file("src/a.txt", "new")
        let dest = try folder("dest")
        try file("dest/a.txt", "old")
        let recorder = ClashRecorder(.skip)
        let change = try await engine.copy([source], into: dest, resolveClash: recorder.resolver, progress: nil)
        XCTAssertTrue(change.isEmpty)
        XCTAssertEqual(try text(dest.appendingPathComponent("a.txt")), "old")
        XCTAssertEqual(recorder.clashes.count, 1)
        let clash = try XCTUnwrap(recorder.clashes.first)
        XCTAssertEqual(clash.source.path, source.path)
        XCTAssertEqual(clash.existing.path, dest.appendingPathComponent("a.txt").path)
        XCTAssertFalse(clash.sourceIsFolder)
        XCTAssertFalse(clash.existingIsFolder)
        XCTAssertEqual(try trashNames(), [])
    }

    func testClashKeepBoth() async throws {
        let source = try file("src/a.txt", "new")
        let dest = try folder("dest")
        try file("dest/a.txt", "old")
        let change = try await engine.copy([source], into: dest, resolveClash: ClashRecorder(.keepBoth).resolver,
                                           progress: nil)
        XCTAssertEqual(try names(dest), ["a (2).txt", "a.txt"])
        XCTAssertEqual(try text(dest.appendingPathComponent("a.txt")), "old")
        XCTAssertEqual(try text(dest.appendingPathComponent("a (2).txt")), "new")
        XCTAssertEqual(change.createdItems.map(\.lastPathComponent), ["a (2).txt"])
    }

    func testClashReplaceTrashesTheOldItemAndUndoBringsItBack() async throws {
        let source = try file("src/a.txt", "new")
        let dest = try folder("dest")
        try file("dest/a.txt", "old")
        let change = try await engine.copy([source], into: dest, resolveClash: ClashRecorder(.replace).resolver,
                                           progress: nil)
        XCTAssertEqual(try text(dest.appendingPathComponent("a.txt")), "new")
        XCTAssertEqual(try trashNames(), ["a.txt"])
        XCTAssertEqual(try text(trashFolder.appendingPathComponent("a.txt")), "old", "replaced means trashed")

        _ = try await engine.undo(change)
        XCTAssertEqual(try names(dest), ["a.txt"])
        XCTAssertEqual(try text(dest.appendingPathComponent("a.txt")), "old")
        // The copy went to the Trash first (as "a (2).txt", the old one was still there), then the old one came back.
        XCTAssertEqual(try trashNames(), ["a (2).txt"])
        XCTAssertEqual(try text(trashFolder.appendingPathComponent("a (2).txt")), "new", "the copy goes to the Trash")
    }

    func testClashFolderOverFile() async throws {
        try file("src/name/inner.txt", "i")
        let dest = try folder("dest")
        try file("dest/name", "a file")
        let recorder = ClashRecorder(.replace)
        _ = try await engine.copy([url("src/name", isFolder: true)], into: dest, resolveClash: recorder.resolver,
                                  progress: nil)
        let clash = try XCTUnwrap(recorder.clashes.first)
        XCTAssertTrue(clash.sourceIsFolder)
        XCTAssertFalse(clash.existingIsFolder)
        XCTAssertEqual(try text(dest.appendingPathComponent("name/inner.txt")), "i")
        XCTAssertEqual(try text(trashFolder.appendingPathComponent("name")), "a file")
    }

    func testApplyToAllAsksOnce() async throws {
        let dest = try folder("dest")
        var sources: [URL] = []
        for n in 1...3 {
            sources.append(try file("src/x\(n).txt", "new\(n)"))
            try file("dest/x\(n).txt", "old\(n)")
        }
        let recorder = ClashRecorder(.keepBoth, applyToAll: true)
        _ = try await engine.copy(sources, into: dest, resolveClash: recorder.resolver, progress: nil)
        XCTAssertEqual(recorder.clashes.count, 1)
        XCTAssertEqual(try names(dest), ["x1 (2).txt", "x1.txt", "x2 (2).txt", "x2.txt", "x3 (2).txt", "x3.txt"])
    }

    func testWithoutApplyToAllAsksEachTime() async throws {
        let dest = try folder("dest")
        let sources = [try file("src/x1.txt"), try file("src/x2.txt")]
        try file("dest/x1.txt")
        try file("dest/x2.txt")
        let recorder = ClashRecorder(.skip)
        _ = try await engine.copy(sources, into: dest, resolveClash: recorder.resolver, progress: nil)
        XCTAssertEqual(recorder.clashes.map(\.source.lastPathComponent), ["x1.txt", "x2.txt"])
    }

    func testClashStopEndsTheOperationAndKeepsDoneItemsUndoable() async throws {
        let dest = try folder("dest")
        let sources = [try file("src/x1.txt", "new1"), try file("src/x2.txt", "new2"), try file("src/x3.txt", "new3")]
        try file("dest/x2.txt", "old2")
        let recorder = ClashRecorder(.stop)
        var partial: FileChange?
        do {
            _ = try await engine.copy(sources, into: dest, resolveClash: recorder.resolver, progress: nil)
            XCTFail("Stop must end the copy")
        } catch FileOperationError.cancelled(let done) {
            partial = done
        }
        XCTAssertEqual(try names(dest), ["x1.txt", "x2.txt"], "x1 is done, x3 never starts")
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("x2.txt"), encoding: .utf8), "old2")
        let done = try XCTUnwrap(partial, "the done item can be undone")
        _ = try await engine.undo(done)
        XCTAssertEqual(try names(dest), ["x2.txt"])
    }

    func testClashSaysHowManyItemsFollow() async throws {
        let dest = try folder("dest")
        var sources: [URL] = []
        for n in 1...3 {
            sources.append(try file("src/x\(n).txt"))
            try file("dest/x\(n).txt")
        }
        let recorder = ClashRecorder(.skip)
        _ = try await engine.copy(sources, into: dest, resolveClash: recorder.resolver, progress: nil)
        XCTAssertEqual(recorder.clashes.map(\.laterItems), [2, 1, 0])
    }

    // MARK: Progress and cancel

    func testProgressTotalsAndReports() async throws {
        engine.allowsCloning = false
        engine.progressInterval = 0
        try data("src/a.bin", Data(repeating: 1, count: 3000))
        try data("src/dir/b.bin", Data(repeating: 2, count: 5000))
        try data("src/dir/c.bin", Data(repeating: 3, count: 7000))
        try link("src/dir/link", to: "b.bin")
        try bigFile("src/big.bin", megabytes: 8)
        let total = Int64(3000 + 5000 + 7000 + 8 << 20)
        let dest = try folder("dest")
        let recorder = ProgressRecorder()
        _ = try await engine.copy([url("src/a.bin"), url("src/dir", isFolder: true), url("src/big.bin")], into: dest,
                                  resolveClash: never, progress: recorder.handler)

        let reports = recorder.reports
        XCTAssertGreaterThan(reports.count, 6)
        XCTAssertTrue(reports.allSatisfy { $0.totalBytes == total && $0.totalItems == 3 })
        XCTAssertTrue(zip(reports, reports.dropFirst()).allSatisfy { $0.completedBytes <= $1.completedBytes },
                      "bytes only go up")
        XCTAssertTrue(reports.allSatisfy { $0.completedBytes <= total })
        XCTAssertEqual(reports.last?.completedBytes, total)
        XCTAssertEqual(reports.last?.completedItems, 3)
        XCTAssertEqual(reports.last?.fraction, 1)
        XCTAssertTrue(reports.contains { $0.currentName == "c.bin" }, "names files inside a folder")
        let bigStart = Int64(15000)
        XCTAssertTrue(reports.contains { $0.completedBytes > bigStart && $0.completedBytes < total },
                      "reports bytes in the middle of a big file")
    }

    func testCancelMidCopyLeavesDoneItemsUndoable() async throws {
        engine.allowsCloning = false
        engine.progressInterval = 0
        let one = try file("src/one.txt", "one")
        let big = try bigFile("src/big.bin", megabytes: 32)
        let two = try file("src/two.txt", "two")
        let dest = try folder("dest")
        let box = TaskBox()
        let recorder = ProgressRecorder()
        recorder.onReport = { progress in
            if progress.currentName == "big.bin", progress.completedBytes > 3 { box.cancel() }
        }
        let engine = self.engine!
        let never = self.never
        let task = Task {
            try await engine.copy([one, big, two], into: dest, resolveClash: never, progress: recorder.handler)
        }
        box.set(task)
        let error = await operationError { _ = try await task.value }
        guard case .cancelled(let partial) = error else { return XCTFail("\(String(describing: error))") }
        let done = try XCTUnwrap(partial)
        XCTAssertEqual(done.createdItems.map(\.lastPathComponent), ["one.txt"])
        XCTAssertEqual(try names(dest), ["one.txt"], "no half-copied big file, no temporary item, nothing after it")
        let lastBytes = try XCTUnwrap(recorder.reports.last?.completedBytes)
        XCTAssertLessThan(lastBytes, 32 << 20, "stopped in the middle")

        _ = try await engine.undo(done)
        XCTAssertEqual(try names(dest), [])
        XCTAssertEqual(try trashNames(), ["one.txt"])
    }

    func testCancelDuringReplaceBringsTheOldItemBack() async throws {
        engine.allowsCloning = false
        engine.progressInterval = 0
        let big = try bigFile("src/big.bin", megabytes: 32)
        let dest = try folder("dest")
        try file("dest/big.bin", "old")
        let box = TaskBox()
        let recorder = ProgressRecorder()
        recorder.onReport = { progress in
            if progress.completedBytes > 0 { box.cancel() }
        }
        let engine = self.engine!
        let replace = ClashRecorder(.replace).resolver
        let task = Task {
            try await engine.copy([big], into: dest, resolveClash: replace, progress: recorder.handler)
        }
        box.set(task)
        let error = await operationError { _ = try await task.value }
        guard case .cancelled(let partial) = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertNil(partial)
        XCTAssertEqual(try names(dest), ["big.bin"])
        XCTAssertEqual(try text(dest.appendingPathComponent("big.bin")), "old")
        XCTAssertEqual(try trashNames(), [])
    }

    func testCancelBeforeStartCopiesNothing() async throws {
        let a = try file("src/a.txt")
        let dest = try folder("dest")
        let engine = self.engine!
        let never = self.never
        let task = Task { () -> FileChange in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.copy([a], into: dest, resolveClash: never, progress: nil)
        }
        let error = await operationError { _ = try await task.value }
        guard case .cancelled(nil) = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(try names(dest), [])
    }
}
