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
}
