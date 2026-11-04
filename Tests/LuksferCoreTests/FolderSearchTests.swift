import Darwin
import XCTest
import UniformTypeIdentifiers
@testable import LuksferCore

final class FolderSearchTests: XCTestCase {
    private func search(_ root: URL, _ query: String, hidden: Bool = false, limit: Int = FolderSearch.defaultLimit) -> (items: [FileItem], stats: FolderSearch.Stats) {
        var items: [FileItem] = []
        let stats = FolderSearch(root: root, query: query, includeHidden: hidden, limit: limit).run(every: 0) { batch, _ in items += batch }
        return (items, stats)
    }

    private func names(_ items: [FileItem]) -> [String] { items.map(\.name).sorted() }

    func testFindsFilesAndFoldersInEverySubfolder() {
        let box = CoreSandbox()
        box.file("report-top.txt")
        box.file("a/b/c/report-deep.txt")
        box.folder("a/report folder")
        box.file("a/other.txt")
        let result = search(box.root, "report")
        XCTAssertEqual(names(result.items), ["report folder", "report-deep.txt", "report-top.txt"])
        XCTAssertEqual(result.items.first { $0.name == "report-deep.txt" }?.url.path,
                       box.root.appendingPathComponent("a/b/c/report-deep.txt").path)
        XCTAssertEqual(result.stats.foldersSearched, 5, "the root, a, a/b, a/b/c and a/report folder")
        XCTAssertEqual(result.stats.foldersNotSearched, 0)
        XCTAssertFalse(result.stats.reachedLimit)
    }

    func testEveryWordMustMatchInAnyCaseAndAccent() {
        let box = CoreSandbox()
        box.file("x/Résumé 2026.PDF")
        box.file("x/resume 2025.pdf")
        XCTAssertEqual(names(search(box.root, "RESUME 2026").items), ["Résumé 2026.PDF"])
    }

    func testTheSearchedFolderIsNotAResultAndAnEmptyQueryFindsNothing() {
        let box = CoreSandbox()
        let root = box.folder("needle")
        box.file("needle/plain.txt")
        XCTAssertEqual(names(search(root, "needle").items), [])
        XCTAssertEqual(search(root, "   ").items.count, 0)
        XCTAssertEqual(search(root, "   ").stats.foldersSearched, 0)
    }

    func testHiddenItemsAndFoldersFollowTheSetting() {
        let box = CoreSandbox()
        box.file(".needle-hidden")
        box.file(".hidden-folder/needle-inside.txt")
        box.file("shown/needle-shown.txt")
        XCTAssertEqual(names(search(box.root, "needle").items), ["needle-shown.txt"])
        XCTAssertEqual(names(search(box.root, "needle", hidden: true).items),
                       [".needle-hidden", "needle-inside.txt", "needle-shown.txt"])
    }

    func testAPackageIsAResultButItsInsideIsNot() {
        let box = CoreSandbox()
        box.file("Needle.app/Contents/needle-inside.txt")
        XCTAssertEqual(names(search(box.root, "needle").items), ["Needle.app"])
    }

    func testLinksAreNotFollowedSoALoopEnds() throws {
        let box = CoreSandbox()
        box.file("a/needle.txt")
        try FileManager.default.createSymbolicLink(at: box.root.appendingPathComponent("a/loop"), withDestinationURL: box.root)
        try FileManager.default.createSymbolicLink(at: box.root.appendingPathComponent("a/needle-link"), withDestinationURL: box.root)
        let result = search(box.root, "needle")
        XCTAssertEqual(names(result.items), ["needle-link", "needle.txt"])
        XCTAssertEqual(result.stats.foldersSearched, 2)
    }

    func testNearestFoldersComeFirstAndTheLimitStopsTheSearch() {
        let box = CoreSandbox()
        box.file("a/b/needle-deep.txt")
        for i in 1...3 { box.file("needle-\(i).txt") }
        let result = search(box.root, "needle", limit: 3)
        XCTAssertEqual(names(result.items), ["needle-1.txt", "needle-2.txt", "needle-3.txt"])
        XCTAssertTrue(result.stats.reachedLimit)
    }

    func testCancelStopsTheSearch() {
        let box = CoreSandbox()
        for i in 1...50 { box.file("f\(i)/needle-\(i).txt") }
        let search = FolderSearch(root: box.root, query: "needle", includeHidden: false)
        var seen = 0
        var batches = 0
        search.run(every: 0) { batch, _ in
            seen += batch.count
            batches += 1
            search.cancel()
        }
        XCTAssertTrue(search.isCancelled)
        XCTAssertEqual(batches, 1)
        XCTAssertLessThan(seen, 50)

        let before = FolderSearch(root: box.root, query: "needle", includeHidden: false)
        before.cancel()
        var none = 0
        let stats = before.run(every: 0) { batch, _ in none += batch.count }
        XCTAssertEqual(none, 0)
        XCTAssertEqual(stats.foldersSearched, 0)
    }

    func testEachResultComesExactlyOnceWithALongInterval() {
        let box = CoreSandbox()
        for i in 1...20 { box.file("f\(i % 4)/needle-\(i).txt") }
        var all: [FileItem] = []
        var batches = 0
        FolderSearch(root: box.root, query: "needle", includeHidden: false).run(every: 60) { batch, _ in
            all += batch
            batches += 1
        }
        XCTAssertEqual(batches, 1, "one last batch at the end")
        XCTAssertEqual(all.count, 20)
        XCTAssertEqual(Set(all.map(\.url)).count, 20)
    }

    func testAFolderItCannotReadIsCountedAndTheRestIsSearched() throws {
        let box = CoreSandbox()
        box.file("open/needle-open.txt")
        box.file("closed/needle-closed.txt")
        let closed = box.root.appendingPathComponent("closed")
        XCTAssertEqual(chmod(closed.path, 0), 0)
        defer { chmod(closed.path, 0o755) }
        let result = search(box.root, "needle")
        XCTAssertEqual(names(result.items), ["needle-open.txt"])
        XCTAssertEqual(result.stats.unreadableFolders, 1)
        XCTAssertEqual(result.stats.foldersNotSearched, 1)
    }

    func testAMissingFolderCountsAsUnreadable() {
        let box = CoreSandbox()
        let result = search(box.root.appendingPathComponent("nope"), "needle")
        XCTAssertEqual(result.items.count, 0)
        XCTAssertEqual(result.stats.unreadableFolders, 1)
    }

    /// The rule that keeps a cloud folder from downloading. A test cannot make a real cloud-only
    /// folder; `LuksferSpike search <folder>` checks a real one.
    func testACloudOnlyFolderIsNeverEntered() {
        let box = CoreSandbox()
        func folder(link: Bool = false, cloud: Bool = false) -> FileItem {
            FileItem(url: box.root.appendingPathComponent("f"), name: "f", isFolder: true, isPackage: false, isSymlink: link,
                     isHidden: false, isCloudOnly: cloud, size: 0, modified: .distantPast, created: .distantPast, type: .folder)
        }
        XCTAssertEqual(FolderSearch.decision(for: folder(), device: 1, parentDevice: 1), .enter)
        XCTAssertEqual(FolderSearch.decision(for: folder(cloud: true), device: 1, parentDevice: 1), .skipCloudOnly)
        XCTAssertEqual(FolderSearch.decision(for: folder(link: true), device: 1, parentDevice: 1), .skipLink)
        XCTAssertEqual(FolderSearch.decision(for: folder(link: true, cloud: true), device: 1, parentDevice: 1), .skipLink)
    }

    func testDownloadsStayOffWhileItRunsAndThePolicyComesBack() {
        let box = CoreSandbox()
        box.file("needle.txt")
        let type = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
        let before = getiopolicy_np(type, IOPOL_SCOPE_THREAD)
        var inside: Int32 = -1
        FolderSearch(root: box.root, query: "needle", includeHidden: false).run(every: 0) { _, _ in
            inside = getiopolicy_np(type, IOPOL_SCOPE_THREAD)
        }
        XCTAssertEqual(inside, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        XCTAssertEqual(getiopolicy_np(type, IOPOL_SCOPE_THREAD), before)
    }

    func testMountPoints() {
        let box = CoreSandbox()
        XCTAssertTrue(FolderSearch.isMountPoint("/"))
        XCTAssertFalse(FolderSearch.isMountPoint(box.root.path))
        XCTAssertFalse(FolderSearch.isMountPoint(box.root.appendingPathComponent("nope").path))
    }

    func testOnlyAMountPointStopsTheSearchAtAnotherDevice() throws {
        let box = CoreSandbox()
        let plain = try XCTUnwrap(DirectoryReader.item(at: box.folder("plain")))
        XCTAssertEqual(FolderSearch.decision(for: plain, device: 2, parentDevice: 1), .enter)
        let system = try XCTUnwrap(DirectoryReader.item(at: URL(fileURLWithPath: "/System/Volumes", isDirectory: true)))
        XCTAssertEqual(FolderSearch.decision(for: system, device: 1, parentDevice: 1), .skipOtherVolume)
    }

    func testADiskMountedInsideIsNotSearched() throws {
        let box = CoreSandbox()
        let image = box.root.appendingPathComponent("disk.dmg").path
        let mount = box.folder("search/mounted").path
        box.file("search/needle-here.txt")
        func hdiutil(_ arguments: [String]) throws -> Int32 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            p.arguments = arguments
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        }
        guard try hdiutil(["create", "-quiet", "-size", "8m", "-fs", "APFS", "-volname", "T", image]) == 0,
              try hdiutil(["attach", "-quiet", "-nobrowse", "-mountpoint", mount, image]) == 0 else {
            throw XCTSkip("this machine cannot mount a disk image")
        }
        defer { _ = try? hdiutil(["detach", "-quiet", "-force", mount]) }
        try Data().write(to: URL(fileURLWithPath: mount).appendingPathComponent("needle-on-disk.txt"))

        let result = search(box.root.appendingPathComponent("search"), "needle")
        XCTAssertEqual(names(result.items), ["needle-here.txt"])
        XCTAssertEqual(result.stats.otherVolumes, 1)
        XCTAssertEqual(names(search(URL(fileURLWithPath: mount), "needle").items), ["needle-on-disk.txt"], "searching the disk itself works")
    }

    func testLocationText() {
        let root = URL(fileURLWithPath: "/fake/Downloads", isDirectory: true)
        func location(_ path: String, _ under: URL) -> String { FolderSearch.location(of: URL(fileURLWithPath: path), under: under) }
        XCTAssertEqual(location("/fake/Downloads/a.txt", root), "Downloads")
        XCTAssertEqual(location("/fake/Downloads/x/y/a.txt", root), "Downloads/x/y")
        XCTAssertEqual(location("/fake/Other/a.txt", root), "/fake/Other", "an item from elsewhere shows its whole path")
        let top = URL(fileURLWithPath: "/", isDirectory: true)
        XCTAssertEqual(location("/a.txt", top), "/")
        XCTAssertEqual(location("/x/y/a.txt", top), "/x/y")
    }

    func testIsInside() {
        let root = URL(fileURLWithPath: "/fake/Downloads", isDirectory: true)
        XCTAssertTrue(FolderSearch.isInside(URL(fileURLWithPath: "/fake/Downloads/x/a.txt"), folder: root))
        XCTAssertFalse(FolderSearch.isInside(URL(fileURLWithPath: "/fake/Downloads2/a.txt"), folder: root))
        XCTAssertFalse(FolderSearch.isInside(root, folder: root))
        XCTAssertTrue(FolderSearch.isInside(URL(fileURLWithPath: "/a.txt"), folder: URL(fileURLWithPath: "/", isDirectory: true)))
    }

    func testTheFilterAndTheSearchMatchTheSameWay() {
        XCTAssertTrue(ListFilter.matches("Résumé 2026.pdf", words: ListFilter.words(in: " resume  2026 ")))
        XCTAssertFalse(ListFilter.matches("Résumé 2026.pdf", words: ListFilter.words(in: "resume 2025")))
        XCTAssertEqual(ListFilter.words(in: "   "), [])
    }
}
