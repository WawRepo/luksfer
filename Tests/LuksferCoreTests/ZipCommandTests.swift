import XCTest
@testable import LuksferCore

final class ZipCommandTests: XCTestCase {
    /// Real zip in a sandbox folder: names that look like its options stay file names, and no command runs.
    func testNamesThatLookLikeOptionsStayFileNames() throws {
        let box = CoreSandbox()
        let folder = box.folder("hostile")
        let names = ["-T", "-TTtouch marker", "--help", "notes.txt"]
        names.forEach { box.file("hostile/\($0)", "text") }
        let zip = box.root.appendingPathComponent("out.zip")

        let run = Process()
        run.executableURL = ZipCommand.executable
        run.currentDirectoryURL = folder
        run.arguments = ZipCommand.arguments(zip: zip.path, names: names)
        try run.run()
        run.waitUntilExit()

        XCTAssertEqual(run.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("marker").path))
        let list = Process(), out = Pipe()
        list.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        list.arguments = ["-Z1", zip.path]
        list.standardOutput = out
        try list.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        list.waitUntilExit()
        XCTAssertEqual(Set(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)), Set(names))
    }

    func testPlanForOneFolderUsesNames() {
        let plan = ZipCommand.plan([URL(fileURLWithPath: "/w/box/a.txt"), URL(fileURLWithPath: "/w/box/sub", isDirectory: true)])
        XCTAssertEqual(plan?.folder.path, "/w/box")
        XCTAssertEqual(plan?.paths, ["a.txt", "sub"])
    }

    func testPlanForSeveralFoldersKeepsPathsBelowTheCommonFolder() {
        let plan = ZipCommand.plan([URL(fileURLWithPath: "/w/box/deep/inner/a.txt"), URL(fileURLWithPath: "/w/box/top.txt"),
                                    URL(fileURLWithPath: "/w/box/deep/other/a.txt")])
        XCTAssertEqual(plan?.folder.path, "/w/box")
        XCTAssertEqual(plan?.paths, ["deep/inner/a.txt", "top.txt", "deep/other/a.txt"])
        XCTAssertNil(ZipCommand.plan([]))
    }

    /// Real zip: search results from two folders, with the same file name in both, all go in.
    func testSearchResultsFromSeveralFoldersAllGoIn() throws {
        let box = CoreSandbox()
        let a = box.file("results/deep/inner/same.txt", "a")
        let b = box.file("results/deep/other/same.txt", "b")
        let c = box.file("results/-T top.txt", "c")
        let plan = try XCTUnwrap(ZipCommand.plan([a, b, c]))
        XCTAssertEqual(plan.folder.standardizedFileURL, box.root.appendingPathComponent("results").standardizedFileURL)
        let zip = box.root.appendingPathComponent("out.zip")
        let run = Process()
        run.executableURL = ZipCommand.executable
        run.currentDirectoryURL = plan.folder
        run.arguments = ZipCommand.arguments(zip: zip.path, names: plan.paths)
        try run.run()
        run.waitUntilExit()
        XCTAssertEqual(run.terminationStatus, 0)
        let list = Process(), out = Pipe()
        list.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        list.arguments = ["-Z1", zip.path]
        list.standardOutput = out
        try list.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        list.waitUntilExit()
        let entries = Set(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init))
        XCTAssertTrue(entries.isSuperset(of: ["deep/inner/same.txt", "deep/other/same.txt", "-T top.txt"]), "\(entries)")
    }

    func testReasonIsShortAndNamesOnlyTheItem() {
        XCTAssertEqual(ZipCommand.reason(output: "ditto: /w/box/secret.txt: Permission denied\n", status: 1),
                       "secret.txt: Permission denied.")
        XCTAssertEqual(ZipCommand.reason(output: "zip I/O error: Permission denied\nzip error: Could not create output file (/w/a.zip)\n", status: 15),
                       "Could not create output file (a.zip).")
        XCTAssertEqual(ZipCommand.reason(output: "zip warning: Permission denied\n", status: 18),
                       "Some items could not be read (Permission denied).")
        XCTAssertEqual(ZipCommand.reason(output: "", status: 1), "")
        XCTAssertEqual(CompressError.failed(zip: "Archive.zip", reason: "").errorDescription,
                       "Luksfer could not make “Archive.zip”. The disk may be full, or an item may not be readable.")
    }
}
