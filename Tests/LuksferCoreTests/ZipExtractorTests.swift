import XCTest
@testable import LuksferCore

/// Real zips and the real `ditto`, inside a sandbox folder. A bad entry can reach only the sandbox.
final class ZipExtractorTests: XCTestCase {
    private let file: UInt32 = 0o100644, link: UInt32 = 0o120777

    private func contents(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    private func text(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: Where the result goes

    func testOneFolderAtTheTopComesOutAsThatFolder() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [
            ("Report/", "", 0o040755), ("Report/a.txt", "a", file), ("Report/sub/b.txt", "b", file)])
        let before = try Data(contentsOf: zip)

        let result = try ZipExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "Report")
        XCTAssertEqual(text(result.appendingPathComponent("a.txt")), "a")
        XCTAssertEqual(text(result.appendingPathComponent("sub/b.txt")), "b")
        XCTAssertEqual(contents(box.root), ["Report", "archive.zip"], "no hidden folder stays behind")
        XCTAssertEqual(try Data(contentsOf: zip), before, "the zip stays as it was")
    }

    func testSeveralItemsAtTheTopComeOutInAFolderNamedAfterTheZip() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("photos.v2.ZIP"), [
            ("a.txt", "a", file), ("b.txt", "b", file)])

        let result = try ZipExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "photos.v2")
        XCTAssertEqual(contents(result), ["a.txt", "b.txt"])
    }

    func testOneFileAtTheTopComesOutAsThatFile() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [("a.txt", "a", file)])

        let result = try ZipExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "a.txt")
        XCTAssertEqual(text(result), "a")
    }

    func testAFinderFileAtTheTopDoesNotCountAsASecondItem() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [
            (".DS_Store", "x", file), ("Report/a.txt", "a", file)])

        XCTAssertEqual(try ZipExtractor.extract(zip).lastPathComponent, "Report")
    }

    func testAZipThatHoldsAZipOfTheSameNameKeepsBoth() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("a.zip"), [("a.zip", "inner", file)])
        let before = try Data(contentsOf: zip)

        let result = try ZipExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "a (2).zip")
        XCTAssertEqual(text(result), "inner")
        XCTAssertEqual(try Data(contentsOf: zip), before)
    }

    // MARK: Nothing is overwritten

    func testATakenFolderNameGetsANumberAndTheOldFolderStaysAsItWas() throws {
        let box = CoreSandbox()
        box.file("Report/keep.txt", "old")
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [("Report/a.txt", "new", file)])

        let result = try ZipExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "Report (2)")
        XCTAssertEqual(contents(box.root.appendingPathComponent("Report")), ["keep.txt"])
        XCTAssertEqual(text(box.root.appendingPathComponent("Report/keep.txt")), "old")
    }

    func testATakenFileNameGetsANumberAndTheOldFileStaysAsItWas() throws {
        let box = CoreSandbox()
        box.file("a.txt", "old")
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [("a.txt", "new", file)])

        let result = try ZipExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "a (2).txt")
        XCTAssertEqual(text(result), "new")
        XCTAssertEqual(text(box.root.appendingPathComponent("a.txt")), "old")
    }

    func testATakenZipFolderNameGetsANumber() throws {
        let box = CoreSandbox()
        box.file("photos/keep.txt", "old")
        let zip = TestZip.write(to: box.root.appendingPathComponent("photos.zip"), [
            ("a.txt", "a", file), ("b.txt", "b", file)])

        XCTAssertEqual(try ZipExtractor.extract(zip).lastPathComponent, "photos (2)")
        XCTAssertEqual(contents(box.root.appendingPathComponent("photos")), ["keep.txt"])
    }

    // MARK: A failed extract leaves nothing behind

    func testADamagedZipThrowsAndLeavesNothing() throws {
        let box = CoreSandbox()
        let good = TestZip.write(to: box.root.appendingPathComponent("good.zip"),
                                 (0..<40).map { ("f\($0).txt", String(repeating: "x", count: 4000), file) })
        let data = try Data(contentsOf: good)
        let cut = box.root.appendingPathComponent("cut.zip")
        try data.prefix(data.count / 2).write(to: cut)
        try FileManager.default.removeItem(at: good)

        XCTAssertThrowsError(try ZipExtractor.extract(cut)) {
            XCTAssertEqual($0 as? ZipExtractError, .failed("cut.zip"))
        }
        XCTAssertEqual(contents(box.root), ["cut.zip"])
    }

    func testAFileThatIsNotAZipThrowsAndLeavesNothing() {
        let box = CoreSandbox()
        let fake = box.file("fake.zip", "this is not a zip")

        XCTAssertThrowsError(try ZipExtractor.extract(fake))
        XCTAssertEqual(contents(box.root), ["fake.zip"])
    }

    func testAPasswordZipSaysSoAndLeavesNothing() throws {
        let box = CoreSandbox()
        box.file("source/secret.txt", "secret")
        let zip = box.root.appendingPathComponent("locked.zip")
        let make = Process()
        make.executableURL = ZipCommand.executable
        make.currentDirectoryURL = box.root.appendingPathComponent("source")
        make.arguments = ["-q", "-P", "made-up", zip.path, "secret.txt"]
        try make.run()
        make.waitUntilExit()
        XCTAssertEqual(make.terminationStatus, 0)

        XCTAssertThrowsError(try ZipExtractor.extract(zip)) {
            XCTAssertEqual($0 as? ZipExtractError, .needsPassword("locked.zip"))
        }
        XCTAssertEqual(contents(box.root), ["locked.zip", "source"])
    }

    /// The link makes `ditto` fail, after it has made the read-only folder.
    func testAFailureRemovesAReadOnlyFolderToo() {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [
            ("ro/", "", 0o040555), ("ro/a.txt", "a", file), ("up", "..", link), ("up/x.txt", "x", file)])

        XCTAssertThrowsError(try ZipExtractor.extract(zip))
        XCTAssertEqual(contents(box.root), ["archive.zip"])
    }

    func testAReadOnlyFolderAtTheTopComesOutWithItsMode() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [
            ("ro/", "", 0o040555), ("ro/a.txt", "a", file)])

        let result = try ZipExtractor.extract(zip)
        defer { chmod(result.path, 0o755) }   // so the sandbox can remove it

        XCTAssertEqual(result.lastPathComponent, "ro")
        XCTAssertEqual(text(result.appendingPathComponent("a.txt")), "a")
        XCTAssertEqual(contents(box.root), ["archive.zip", "ro"])
        var info = stat()
        XCTAssertEqual(lstat(result.path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o555)
    }

    // MARK: Bad entries stay inside

    func testDotsInAnEntryStayInside() throws {
        let box = CoreSandbox()
        let level = box.folder("one/two")
        let zip = TestZip.write(to: level.appendingPathComponent("bad.zip"), [
            ("../up-one.txt", "x", file), ("ok/../../../up-three.txt", "x", file), ("fine.txt", "x", file)])

        let result = try ZipExtractor.extract(zip)

        XCTAssertEqual(contents(level), ["bad", "bad.zip"])
        XCTAssertEqual(contents(box.root.appendingPathComponent("one")), ["two"])
        XCTAssertEqual(contents(box.root), ["one"])
        XCTAssertEqual(contents(result), ["fine.txt", "up-one.txt", "up-three.txt"])
    }

    func testAnAbsolutePathInAnEntryStaysInside() throws {
        let box = CoreSandbox()
        let level = box.folder("one")
        let outside = box.root.appendingPathComponent("outside.txt")
        let zip = TestZip.write(to: level.appendingPathComponent("bad.zip"), [
            (outside.path, "x", file), ("fine.txt", "x", file)])

        let result = try ZipExtractor.extract(zip)

        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(contents(result).contains("fine.txt"))
    }

    func testAnEntryCannotWriteThroughALinkFromTheZip() {
        let box = CoreSandbox()
        let level = box.folder("one")
        let zip = TestZip.write(to: level.appendingPathComponent("bad.zip"), [
            ("up", "..", link), ("up/outside.txt", "x", file), ("fine.txt", "x", file)])

        XCTAssertThrowsError(try ZipExtractor.extract(zip))
        XCTAssertEqual(contents(level), ["bad.zip"])
        XCTAssertEqual(contents(box.root), ["one"])
    }

    func testASetuidBitDoesNotComeOut() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [("tool", "#!/bin/sh\n", 0o104755)])

        let result = try ZipExtractor.extract(zip)

        var info = stat()
        XCTAssertEqual(lstat(result.path, &info), 0)
        XCTAssertEqual(info.st_mode & S_ISUID, 0)
    }

    // MARK: macOS details

    func testAQuarantineMarkCarriesOverToWhatComesOut() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("download.zip"), [
            ("Top/run.command", "#!/bin/sh\n", 0o100755), ("Top/a.txt", "a", file)])
        let mark = "0083;6728a000;Test;"
        XCTAssertEqual(setxattr(zip.path, "com.apple.quarantine", mark, mark.utf8.count, 0, 0), 0)

        let result = try ZipExtractor.extract(zip)

        for name in ["run.command", "a.txt"] {
            let size = getxattr(result.appendingPathComponent(name).path, "com.apple.quarantine", nil, 0, 0, 0)
            XCTAssertGreaterThan(size, 0, "\(name) must keep the mark")
        }
    }

    /// A zip from our own Compress: the attribute comes back, and `__MACOSX` does not show up.
    func testAZipFromCompressComesBackWithItsAttributes() throws {
        let box = CoreSandbox()
        let source = box.file("source/Report/r.txt", "r")
        let value = "kept"
        XCTAssertEqual(setxattr(source.path, "user.test", value, value.utf8.count, 0, 0), 0)
        let zip = box.root.appendingPathComponent("own.zip")
        let make = Process()
        make.executableURL = ZipExtractor.executable
        make.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.deletingLastPathComponent().path, zip.path]
        try make.run()
        make.waitUntilExit()
        XCTAssertEqual(make.terminationStatus, 0)

        let result = try ZipExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "Report")
        XCTAssertEqual(contents(result), ["r.txt"])
        XCTAssertEqual(contents(box.root), ["Report", "own.zip", "source"])
        XCTAssertGreaterThan(getxattr(result.appendingPathComponent("r.txt").path, "user.test", nil, 0, 0, 0), 0)
    }

    func testANameThatLooksLikeAnOptionStaysAFileName() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("-x -k \"odd\".zip"), [
            ("a.txt", "a", file), ("b.txt", "b", file)])

        XCTAssertEqual(try ZipExtractor.extract(zip).lastPathComponent, "-x -k \"odd\"")
    }

    func testOnlyAFileEndingInZipCanBeExtracted() throws {
        let box = CoreSandbox()
        func item(_ url: URL) throws -> FileItem { try XCTUnwrap(DirectoryReader.item(at: url)) }
        XCTAssertTrue(ZipExtractor.canExtract(try item(box.file("a.zip"))))
        XCTAssertTrue(ZipExtractor.canExtract(try item(box.file("b.ZIP"))))
        XCTAssertFalse(ZipExtractor.canExtract(try item(box.file("c.txt"))))
        XCTAssertFalse(ZipExtractor.canExtract(try item(box.file("zip"))))
        XCTAssertFalse(ZipExtractor.canExtract(try item(box.folder("folder.zip"))))
    }
}

/// Writes a stored (not compressed) zip with any entry name and mode, also ones a real zip tool
/// refuses to make. A mode with the link type makes a link, and its contents are the link target.
enum TestZip {
    @discardableResult
    static func write(to url: URL, _ entries: [(name: String, contents: String, mode: UInt32)]) -> URL {
        var body = Data(), central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8), data = Data(entry.contents.utf8), offset = UInt32(body.count)
            let crc = crc32(data)
            var shared = Data()
            shared.append(le16(20)); shared.append(le16(0x0800)); shared.append(le16(0))   // version, UTF-8 names, stored
            shared.append(le16(0)); shared.append(le16(0x21))                              // time, date
            shared.append(le32(crc)); shared.append(le32(UInt32(data.count))); shared.append(le32(UInt32(data.count)))
            shared.append(le16(UInt16(name.count))); shared.append(le16(0))
            body.append(le32(0x0403_4b50)); body.append(shared); body.append(name); body.append(data)
            central.append(le32(0x0201_4b50)); central.append(le16(0x0314))                // made on Unix
            central.append(shared)
            central.append(le16(0)); central.append(le16(0)); central.append(le16(0))      // comment, disk, internal
            central.append(le32(entry.mode << 16)); central.append(le32(offset)); central.append(name)
        }
        var end = Data()
        end.append(le32(0x0605_4b50)); end.append(le16(0)); end.append(le16(0))
        end.append(le16(UInt16(entries.count))); end.append(le16(UInt16(entries.count)))
        end.append(le32(UInt32(central.count))); end.append(le32(UInt32(body.count))); end.append(le16(0))
        try! (body + central + end).write(to: url)
        return url
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
