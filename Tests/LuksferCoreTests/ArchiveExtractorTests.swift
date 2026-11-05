import XCTest
@testable import LuksferCore

/// Real archives and the real `ditto` and `tar`, inside a sandbox folder. A bad entry can reach only
/// the sandbox.
final class ArchiveExtractorTests: XCTestCase {
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

        let result = try ArchiveExtractor.extract(zip)

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

        let result = try ArchiveExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "photos.v2")
        XCTAssertEqual(contents(result), ["a.txt", "b.txt"])
    }

    func testOneFileAtTheTopComesOutAsThatFile() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [("a.txt", "a", file)])

        let result = try ArchiveExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "a.txt")
        XCTAssertEqual(text(result), "a")
    }

    func testAFinderFileAtTheTopDoesNotCountAsASecondItem() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [
            (".DS_Store", "x", file), ("Report/a.txt", "a", file)])

        XCTAssertEqual(try ArchiveExtractor.extract(zip).lastPathComponent, "Report")
    }

    func testAZipThatHoldsAZipOfTheSameNameKeepsBoth() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("a.zip"), [("a.zip", "inner", file)])
        let before = try Data(contentsOf: zip)

        let result = try ArchiveExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "a (2).zip")
        XCTAssertEqual(text(result), "inner")
        XCTAssertEqual(try Data(contentsOf: zip), before)
    }

    // MARK: Nothing is overwritten

    func testATakenFolderNameGetsANumberAndTheOldFolderStaysAsItWas() throws {
        let box = CoreSandbox()
        box.file("Report/keep.txt", "old")
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [("Report/a.txt", "new", file)])

        let result = try ArchiveExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "Report (2)")
        XCTAssertEqual(contents(box.root.appendingPathComponent("Report")), ["keep.txt"])
        XCTAssertEqual(text(box.root.appendingPathComponent("Report/keep.txt")), "old")
    }

    func testATakenFileNameGetsANumberAndTheOldFileStaysAsItWas() throws {
        let box = CoreSandbox()
        box.file("a.txt", "old")
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [("a.txt", "new", file)])

        let result = try ArchiveExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "a (2).txt")
        XCTAssertEqual(text(result), "new")
        XCTAssertEqual(text(box.root.appendingPathComponent("a.txt")), "old")
    }

    func testATakenZipFolderNameGetsANumber() throws {
        let box = CoreSandbox()
        box.file("photos/keep.txt", "old")
        let zip = TestZip.write(to: box.root.appendingPathComponent("photos.zip"), [
            ("a.txt", "a", file), ("b.txt", "b", file)])

        XCTAssertEqual(try ArchiveExtractor.extract(zip).lastPathComponent, "photos (2)")
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

        XCTAssertThrowsError(try ArchiveExtractor.extract(cut)) {
            XCTAssertEqual($0 as? ArchiveExtractError, .failed("cut.zip"))
        }
        XCTAssertEqual(contents(box.root), ["cut.zip"])
    }

    func testAFileThatIsNotAZipThrowsAndLeavesNothing() {
        let box = CoreSandbox()
        let fake = box.file("fake.zip", "this is not a zip")

        XCTAssertThrowsError(try ArchiveExtractor.extract(fake))
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

        XCTAssertThrowsError(try ArchiveExtractor.extract(zip)) {
            XCTAssertEqual($0 as? ArchiveExtractError, .needsPassword("locked.zip"))
        }
        XCTAssertEqual(contents(box.root), ["locked.zip", "source"])
    }

    /// The link makes `ditto` fail, after it has made the read-only folder.
    func testAFailureRemovesAReadOnlyFolderToo() {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [
            ("ro/", "", 0o040555), ("ro/a.txt", "a", file), ("up", "..", link), ("up/x.txt", "x", file)])

        XCTAssertThrowsError(try ArchiveExtractor.extract(zip))
        XCTAssertEqual(contents(box.root), ["archive.zip"])
    }

    func testAReadOnlyFolderAtTheTopComesOutWithItsMode() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [
            ("ro/", "", 0o040555), ("ro/a.txt", "a", file)])

        let result = try ArchiveExtractor.extract(zip)
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

        let result = try ArchiveExtractor.extract(zip)

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

        let result = try ArchiveExtractor.extract(zip)

        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(contents(result).contains("fine.txt"))
    }

    func testAnEntryCannotWriteThroughALinkFromTheZip() {
        let box = CoreSandbox()
        let level = box.folder("one")
        let zip = TestZip.write(to: level.appendingPathComponent("bad.zip"), [
            ("up", "..", link), ("up/outside.txt", "x", file), ("fine.txt", "x", file)])

        XCTAssertThrowsError(try ArchiveExtractor.extract(zip))
        XCTAssertEqual(contents(level), ["bad.zip"])
        XCTAssertEqual(contents(box.root), ["one"])
    }

    func testASetuidBitDoesNotComeOut() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("archive.zip"), [("tool", "#!/bin/sh\n", 0o104755)])

        let result = try ArchiveExtractor.extract(zip)

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

        let result = try ArchiveExtractor.extract(zip)

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
        make.executableURL = ArchiveExtractor.ditto
        make.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.deletingLastPathComponent().path, zip.path]
        try make.run()
        make.waitUntilExit()
        XCTAssertEqual(make.terminationStatus, 0)

        let result = try ArchiveExtractor.extract(zip)

        XCTAssertEqual(result.lastPathComponent, "Report")
        XCTAssertEqual(contents(result), ["r.txt"])
        XCTAssertEqual(contents(box.root), ["Report", "own.zip", "source"])
        XCTAssertGreaterThan(getxattr(result.appendingPathComponent("r.txt").path, "user.test", nil, 0, 0, 0), 0)
    }

    func testANameThatLooksLikeAnOptionStaysAFileName() throws {
        let box = CoreSandbox()
        let zip = TestZip.write(to: box.root.appendingPathComponent("-x -k \"odd\".zip"), [
            ("a.txt", "a", file), ("b.txt", "b", file)])

        XCTAssertEqual(try ArchiveExtractor.extract(zip).lastPathComponent, "-x -k \"odd\"")
    }

    func testOnlyAFileWithAKnownArchiveEndingCanBeExtracted() throws {
        let box = CoreSandbox()
        func item(_ url: URL) throws -> FileItem { try XCTUnwrap(DirectoryReader.item(at: url)) }
        for name in ["a.zip", "b.ZIP", "c.7z", "d.tar", "e.tar.gz", "f.TGZ", "g.tar.bz2", "h.tbz2",
                     "i.tar.xz", "j.txz", "k.v2.Tar.Gz"] {
            XCTAssertTrue(ArchiveExtractor.canExtract(try item(box.file(name))), name)
        }
        for name in ["c.txt", "zip", ".zip", ".tar.gz", "notes.gz", "notes.bz2", "notes.xz", "a.rar", "zip.txt"] {
            XCTAssertFalse(ArchiveExtractor.canExtract(try item(box.file(name))), name)
        }
        XCTAssertFalse(ArchiveExtractor.canExtract(try item(box.folder("folder.zip"))))
        XCTAssertFalse(ArchiveExtractor.canExtract(try item(box.folder("folder.tar.gz"))))
    }

    func testAFileWithAnotherEndingThrowsAndLeavesNothing() {
        let box = CoreSandbox()
        let other = box.file("notes.gz", "x")

        XCTAssertThrowsError(try ArchiveExtractor.extract(other)) {
            XCTAssertEqual($0 as? ArchiveExtractError, .failed("notes.gz"))
        }
        XCTAssertEqual(contents(box.root), ["notes.gz"])
    }

    // MARK: 7z and tar

    /// Makes an archive with macOS's tar, from items in `folder`.
    @discardableResult
    private func tarArchive(_ url: URL, of folder: URL, _ items: [String], _ options: [String]) throws -> URL {
        let make = Process()
        make.executableURL = ArchiveExtractor.tar
        make.arguments = ["-c"] + options + ["-f", url.path, "-C", folder.path] + items
        make.standardError = FileHandle.nullDevice
        try make.run()
        make.waitUntilExit()
        XCTAssertEqual(make.terminationStatus, 0, url.lastPathComponent)
        return url
    }

    func testEachTarAnd7zEndingExtracts() throws {
        let box = CoreSandbox()
        let source = box.folder("source")
        box.file("source/Report/a.txt", "a")
        let kinds: [(String, [String])] = [
            ("r.tar", []), ("r.tar.gz", ["-z"]), ("r.tgz", ["-z"]), ("r.tar.bz2", ["-j"]), ("r.tbz2", ["-j"]),
            ("r.tar.xz", ["-J"]), ("r.txz", ["-J"]), ("r.7z", ["--format", "7zip"]), ("R.TAR.GZ", ["-z"])]
        for (index, (name, options)) in kinds.enumerated() {
            let level = box.folder("out-\(index)")   // the disk ignores case, so not the name
            let archive = try tarArchive(level.appendingPathComponent(name), of: source, ["Report"], options)
            let before = try Data(contentsOf: archive)

            let result = try ArchiveExtractor.extract(archive)

            XCTAssertEqual(result.lastPathComponent, "Report", name)
            XCTAssertEqual(text(result.appendingPathComponent("a.txt")), "a", name)
            XCTAssertEqual(contents(level), ["Report", name].sorted(), "\(name): no hidden folder stays behind")
            XCTAssertEqual(try Data(contentsOf: archive), before, "\(name) stays as it was")
        }
    }

    func testSeveralItemsAtTheTopComeOutInAFolderWithoutTheWholeEnding() throws {
        let box = CoreSandbox()
        let source = box.folder("source")
        box.file("source/a.txt", "a")
        box.file("source/b.txt", "b")
        let tgz = try tarArchive(box.root.appendingPathComponent("photos.v2.tar.gz"), of: source, ["a.txt", "b.txt"], ["-z"])
        let seven = try tarArchive(box.root.appendingPathComponent("notes.7z"), of: source, ["a.txt", "b.txt"], ["--format", "7zip"])

        XCTAssertEqual(try ArchiveExtractor.extract(tgz).lastPathComponent, "photos.v2")
        let result = try ArchiveExtractor.extract(seven)
        XCTAssertEqual(result.lastPathComponent, "notes")
        XCTAssertEqual(contents(result), ["a.txt", "b.txt"])
    }

    /// `tar -czf x.tgz -C folder .` puts a "./" entry first. Its items count, not the "." itself.
    func testATarOfAFolderDotComesOutInAFolderNamedAfterTheTar() throws {
        let box = CoreSandbox()
        let source = box.folder("source")
        box.file("source/a.txt", "a")
        box.file("source/b.txt", "b")
        let tgz = try tarArchive(box.root.appendingPathComponent("backup.tgz"), of: source, ["."], ["-z"])

        let result = try ArchiveExtractor.extract(tgz)

        XCTAssertEqual(result.lastPathComponent, "backup")
        XCTAssertEqual(contents(result), ["a.txt", "b.txt"])
    }

    func testATakenNameGetsANumberForATarToo() throws {
        let box = CoreSandbox()
        let source = box.folder("source")
        box.file("source/Report/a.txt", "new")
        let tgz = try tarArchive(box.root.appendingPathComponent("r.tgz"), of: source, ["Report"], ["-z"])
        box.file("Report/keep.txt", "old")

        XCTAssertEqual(try ArchiveExtractor.extract(tgz).lastPathComponent, "Report (2)")
        XCTAssertEqual(contents(box.root.appendingPathComponent("Report")), ["keep.txt"])
        XCTAssertEqual(text(box.root.appendingPathComponent("Report/keep.txt")), "old")
    }

    func testADamagedTarGzThrowsAndLeavesNothing() throws {
        let box = CoreSandbox()
        let source = box.folder("source")
        for index in 0..<20 {
            let noise = Data((0..<20_000).map { _ in UInt8.random(in: 0...255) })
            try noise.write(to: source.appendingPathComponent("f\(index).bin"))
        }
        let good = try tarArchive(box.root.appendingPathComponent("good.tar.gz"), of: source, ["."], ["-z"])
        let data = try Data(contentsOf: good)
        let cut = box.root.appendingPathComponent("cut.tar.gz")
        try data.prefix(data.count / 2).write(to: cut)
        try FileManager.default.removeItem(at: good)
        try FileManager.default.removeItem(at: source)

        XCTAssertThrowsError(try ArchiveExtractor.extract(cut)) {
            XCTAssertEqual($0 as? ArchiveExtractError, .failed("cut.tar.gz"))
        }
        XCTAssertEqual(contents(box.root), ["cut.tar.gz"])
    }

    func testAFileThatIsNotA7zThrowsAndLeavesNothing() {
        let box = CoreSandbox()
        let fake = box.file("fake.7z", "this is not a 7z")

        XCTAssertThrowsError(try ArchiveExtractor.extract(fake)) {
            XCTAssertEqual($0 as? ArchiveExtractError, .failed("fake.7z"))
        }
        XCTAssertEqual(contents(box.root), ["fake.7z"])
    }

    /// Both made with 7-Zip and the password "made-up": one file "a.txt" with made-up text.
    /// "hidden.7z" also hides the file names (`-mhe=on`).
    private static let locked7z = "N3q8ryccAAS81vsGEAAAAAAAAABiAAAAAAAAAJnYolMrGUM/5/MyKxPrSKtdpdC1AQQGAAEJEAAHCwEAAiQG8QcBElMPXyJHjrO8+HzL05UnOJ7x6iEhAQABAAwQDAAICgGFUIWeAAAFARkBABENAGEALgB0AHgAdAAAABQKAQAAOKWjeG3dARUGAQAggKSBAAA="
    private static let hidden7z = "N3q8ryccAASjZFVDgAAAAAAAAAAuAAAAAAAAANXcQW61Hq3FQCpd1l8YeRJK2yJhM8tLGaYP4ZM4AyJ6DbaG8VrC7e4y8K/+OM1FymwgxRHjt7CTcFgmhg1Gaole3Dit0JJ88rHbj+jfWWUYfEwcLAa+AwMHtxW7i+TISLoKLfQXU51zvEOYhAuowuHuSt0WZ9k89A5dpaILPgzYeuBABBcGEAEJcAAHCwEAASQG8QcBElMPDridqR51OSotsGK6mbwYOAxiCgGJU+tlAAA="

    func testAPassword7zSaysSoAndLeavesNothing() throws {
        let box = CoreSandbox()
        for (name, bytes) in [("locked.7z", Self.locked7z), ("hidden.7z", Self.hidden7z)] {
            let level = box.folder("out-\(name)")
            let archive = level.appendingPathComponent(name)
            try XCTUnwrap(Data(base64Encoded: bytes)).write(to: archive)

            XCTAssertThrowsError(try ArchiveExtractor.extract(archive), name) {
                XCTAssertEqual($0 as? ArchiveExtractError, .needsPassword(name))
            }
            XCTAssertEqual(contents(level), [name])
        }
    }

    func testDotsInATarEntryFailTheWholeExtractAndLeaveNothing() {
        let box = CoreSandbox()
        let level = box.folder("one/two")
        let tar = TestTar.write(to: level.appendingPathComponent("bad.tar"), [
            ("fine.txt", "x", 0o644, "0"), ("../up-one.txt", "x", 0o644, "0"), ("ok/../../../up-three.txt", "x", 0o644, "0")])

        XCTAssertThrowsError(try ArchiveExtractor.extract(tar)) {
            XCTAssertEqual($0 as? ArchiveExtractError, .failed("bad.tar"))
        }
        XCTAssertEqual(contents(level), ["bad.tar"])
        XCTAssertEqual(contents(box.root.appendingPathComponent("one")), ["two"])
        XCTAssertEqual(contents(box.root), ["one"])
    }

    func testAnAbsolutePathInATarEntryStaysInside() throws {
        let box = CoreSandbox()
        let level = box.folder("one")
        let outside = box.root.appendingPathComponent("outside.txt")
        let tar = TestTar.write(to: level.appendingPathComponent("bad.tar"), [
            (outside.path, "x", 0o644, "0"), ("fine.txt", "x", 0o644, "0")])

        let result = try ArchiveExtractor.extract(tar)

        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertEqual(contents(box.root), ["one"])
        XCTAssertEqual(contents(level), ["bad", "bad.tar"])
        XCTAssertTrue(contents(result).contains("fine.txt"))
    }

    func testATarEntryCannotWriteThroughALinkFromTheTar() {
        let box = CoreSandbox()
        let level = box.folder("one")
        let tar = TestTar.write(to: level.appendingPathComponent("bad.tar"), [
            ("up", "..", 0o777, "2"), ("up/outside.txt", "x", 0o644, "0"), ("fine.txt", "x", 0o644, "0")])

        XCTAssertThrowsError(try ArchiveExtractor.extract(tar))
        XCTAssertEqual(contents(level), ["bad.tar"])
        XCTAssertEqual(contents(box.root), ["one"])
    }

    /// A hard link to a file outside would let an edit inside the result change that file.
    func testAHardLinkInATarCannotReachAFileOutside() throws {
        let box = CoreSandbox()
        let secret = box.file("secret.txt", "owner")
        let level = box.folder("one/two")
        for (name, target) in [("abs.tar", secret.path), ("dots.tar", "../../secret.txt")] {
            let tar = TestTar.write(to: level.appendingPathComponent(name), [
                ("fine.txt", "x", 0o644, "0"), ("h", target, 0o644, "1")])

            XCTAssertThrowsError(try ArchiveExtractor.extract(tar), name)
            var info = stat()
            XCTAssertEqual(lstat(secret.path, &info), 0)
            XCTAssertEqual(info.st_nlink, 1, "\(name): no second name for the file outside")
            XCTAssertEqual(contents(level), [name])
            try FileManager.default.removeItem(at: tar)
        }
        XCTAssertEqual(text(secret), "owner")
    }

    func testASetuidBitInATarDoesNotComeOut() throws {
        let box = CoreSandbox()
        let tar = TestTar.write(to: box.root.appendingPathComponent("archive.tar"), [("tool", "#!/bin/sh\n", 0o4755, "0")])

        let result = try ArchiveExtractor.extract(tar)

        var info = stat()
        XCTAssertEqual(lstat(result.path, &info), 0)
        XCTAssertEqual(info.st_mode & S_ISUID, 0)
    }

    func testAQuarantineMarkCarriesOverFromATarGzAndA7z() throws {
        let box = CoreSandbox()
        let source = box.folder("source")
        box.file("source/Top/a.txt", "a")
        for (name, options) in [("download.tar.gz", ["-z"]), ("download.7z", ["--format", "7zip"])] {
            let level = box.folder("out-\(name)")
            let archive = try tarArchive(level.appendingPathComponent(name), of: source, ["Top"], options)
            let mark = "0083;6728a000;Test;"
            XCTAssertEqual(setxattr(archive.path, "com.apple.quarantine", mark, mark.utf8.count, 0, 0), 0)

            let result = try ArchiveExtractor.extract(archive)

            let size = getxattr(result.appendingPathComponent("a.txt").path, "com.apple.quarantine", nil, 0, 0, 0)
            XCTAssertGreaterThan(size, 0, "\(name): a.txt must keep the mark")
        }
    }

    func testATarNameThatLooksLikeAnOptionStaysAFileName() throws {
        let box = CoreSandbox()
        let source = box.folder("source")
        box.file("source/a.txt", "a")
        box.file("source/b.txt", "b")
        let tgz = try tarArchive(box.root.appendingPathComponent("-x -f \"odd\".tar.gz"), of: source, ["a.txt", "b.txt"], ["-z"])

        XCTAssertEqual(try ArchiveExtractor.extract(tgz).lastPathComponent, "-x -f \"odd\"")
    }
}

/// Writes a plain (ustar) tar with any entry name, mode and type, also ones a real tar tool
/// refuses to make. Type "0" is a file, "1" a hard link, "2" a link and "5" a folder. For a link,
/// `contents` is the target.
enum TestTar {
    @discardableResult
    static func write(to url: URL, _ entries: [(name: String, contents: String, mode: Int, type: Character)]) -> URL {
        var out = Data()
        for entry in entries {
            let isFile = entry.type == "0"
            let data = isFile ? Data(entry.contents.utf8) : Data()
            var header = Data(count: 512)
            func put(_ text: String, at offset: Int) {
                let bytes = Array(text.utf8)
                header.replaceSubrange(offset..<offset + bytes.count, with: bytes)
            }
            func octal(_ value: Int, width: Int) -> String {
                let digits = String(value, radix: 8)
                return String(repeating: "0", count: width - 1 - digits.count) + digits + "\0"
            }
            // A long name goes in two parts: the folders in "prefix", the rest in "name".
            var name = entry.name, prefix = ""
            if name.utf8.count > 100, let cut = name.lastIndex(of: "/") {
                prefix = String(name[..<cut]); name = String(name[name.index(after: cut)...])
            }
            precondition(name.utf8.count <= 100 && prefix.utf8.count <= 155, "name too long for a test tar")
            put(name, at: 0)
            put(octal(entry.mode, width: 8), at: 100)
            put(octal(0, width: 8), at: 108)
            put(octal(0, width: 8), at: 116)
            put(octal(data.count, width: 12), at: 124)
            put(octal(0, width: 12), at: 136)
            put("        ", at: 148)
            put(String(entry.type), at: 156)
            if !isFile { put(entry.contents, at: 157) }
            put("ustar\u{0}00", at: 257)
            put(prefix, at: 345)
            put(octal(header.reduce(0) { $0 + Int($1) }, width: 7) + " ", at: 148)
            out.append(header)
            out.append(data)
            out.append(Data(count: (512 - data.count % 512) % 512))
        }
        out.append(Data(count: 1024))
        try! out.write(to: url)
        return url
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
