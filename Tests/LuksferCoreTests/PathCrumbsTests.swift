import XCTest
@testable import LuksferCore

final class PathCrumbsTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/alex", isDirectory: true)

    private func crumbs(_ path: String) -> [PathCrumb] {
        PathCrumbs.crumbs(for: URL(fileURLWithPath: path, isDirectory: true),
                          home: home, userName: "alex", rootName: "Macintosh HD")
    }

    private func titles(_ path: String) -> [String] { crumbs(path).map(\.title) }
    private func paths(_ path: String) -> [String] { crumbs(path).map(\.url.path) }

    func testUnderHomeStartsWithTheUserName() {
        XCTAssertEqual(titles("/Users/alex/Projects/Luksfer"), ["alex", "Projects", "Luksfer"])
        XCTAssertEqual(paths("/Users/alex/Projects/Luksfer"),
                       ["/Users/alex", "/Users/alex/Projects", "/Users/alex/Projects/Luksfer"])
        XCTAssertEqual(titles("/Users/alex"), ["alex"])
        XCTAssertTrue(crumbs("/Users/alex/Projects")[1].url.hasDirectoryPath)
    }

    func testOutsideHomeStartsWithTheStartupDisk() {
        XCTAssertEqual(titles("/"), ["Macintosh HD"])
        XCTAssertEqual(paths("/"), ["/"])
        XCTAssertEqual(titles("/Applications/Utilities"), ["Macintosh HD", "Applications", "Utilities"])
        XCTAssertEqual(paths("/Applications/Utilities"), ["/", "/Applications", "/Applications/Utilities"])
        XCTAssertEqual(titles("/Users"), ["Macintosh HD", "Users"])
        XCTAssertEqual(titles("/Users/alexandra/Notes"), ["Macintosh HD", "Users", "alexandra", "Notes"])
        XCTAssertEqual(titles("/Volumes"), ["Macintosh HD", "Volumes"])
    }

    func testVolumesStartWithTheVolumeName() {
        XCTAssertEqual(titles("/Volumes/Backup Disk/Photos/2024"), ["Backup Disk", "Photos", "2024"])
        XCTAssertEqual(paths("/Volumes/Backup Disk/Photos"),
                       ["/Volumes/Backup Disk", "/Volumes/Backup Disk/Photos"])
        XCTAssertEqual(titles("/Volumes/USB"), ["USB"])
    }

    func testGoogleDriveCollapsesIntoOneCrumbWithoutTheAccount() {
        let account = "GoogleDrive-sample-account"
        let drive = "/Users/alex/Library/CloudStorage/" + account
        let found = crumbs(drive + "/My Drive/Notes")
        XCTAssertEqual(found.map(\.title), ["alex", "Google Drive", "My Drive", "Notes"])
        XCTAssertEqual(found[1].url.path, drive)
        XCTAssertEqual(found[2].url.path, drive + "/My Drive")
        XCTAssertFalse(found.contains { $0.title.contains("sample") })
        XCTAssertEqual(titles(drive), ["alex", "Google Drive"])
    }

    func testOtherCloudProviders() {
        let storage = "/Users/alex/Library/CloudStorage/"
        XCTAssertEqual(titles(storage + "OneDrive-Personal/Docs"), ["alex", "OneDrive", "Docs"])
        XCTAssertEqual(titles(storage + "Dropbox/Docs"), ["alex", "Dropbox", "Docs"])
        XCTAssertEqual(titles(storage + "ProtonDrive-sample.person/Docs"), ["alex", "Proton Drive", "Docs"])
        XCTAssertEqual(titles(storage + "pCloudDrive"), ["alex", "pCloud Drive"])
        XCTAssertEqual(titles("/Users/alex/Library/Mobile Documents/com~apple~CloudDocs/Notes"),
                       ["alex", "iCloud Drive", "Notes"])
    }

    func testCloudStorageItselfIsNotCollapsed() {
        XCTAssertEqual(titles("/Users/alex/Library/CloudStorage"), ["alex", "Library", "CloudStorage"])
        XCTAssertEqual(titles("/Users/alex/Library"), ["alex", "Library"])
    }

    func testTrailingAndDuplicateSlashesAreIgnored() {
        XCTAssertEqual(titles("/Users//alex/Projects/"), ["alex", "Projects"])
    }
}
