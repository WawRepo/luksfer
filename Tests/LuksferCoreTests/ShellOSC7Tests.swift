import XCTest
@testable import LuksferCore

final class ShellOSC7Tests: XCTestCase {
    func testDecodesHostAndPercentEscapes() {
        XCTAssertEqual(OSC7.folder(fromPayload: "file://mac.local/a%20b/c")?.path, "/a b/c")
        XCTAssertEqual(OSC7.host(fromPayload: "file://mac.local/a%20b/c"), "mac.local")
        XCTAssertEqual(OSC7.folder(fromPayload: "file://h/100%25/it%27s")?.path, "/100%/it's")
    }

    func testNoHost() {
        XCTAssertEqual(OSC7.folder(fromPayload: "file:///Users/someone")?.path, "/Users/someone")
        XCTAssertEqual(OSC7.host(fromPayload: "file:///Users/someone"), "")
        XCTAssertEqual(OSC7.folder(fromPayload: "file:///")?.path, "/")
    }

    func testUnicode() {
        XCTAssertEqual(OSC7.folder(fromPayload: "file://h/za%C5%BC%C3%B3%C5%82%C4%87")?.path, "/zażółć")
        XCTAssertEqual(OSC7.folder(fromPayload: "file://h/%E6%96%87%E4%BB%B6")?.path, "/文件")
        XCTAssertEqual(OSC7.folder(fromPayload: "file://h/zaż ółć")?.path, "/zaż ółć")
    }

    func testSchemeIgnoresCase() {
        XCTAssertEqual(OSC7.folder(fromPayload: "FILE://h/a")?.path, "/a")
    }

    func testGarbage() {
        for payload in ["", "hello", "/plain/path", "file://", "file:/a", "file://host",
                        "http://h/a", "file://h/a%zz", "file://h/a%", "file://h/a%00b",
                        "kitty-shell-cwd://h/a"] {
            XCTAssertNil(OSC7.folder(fromPayload: payload), payload.debugDescription)
        }
        XCTAssertNil(OSC7.host(fromPayload: "http://h/a"))
    }

    func testLocalHost() {
        XCTAssertTrue(OSC7.isLocal(host: "", localHostName: "Mac"))
        XCTAssertTrue(OSC7.isLocal(host: "localhost", localHostName: "Mac"))
        XCTAssertTrue(OSC7.isLocal(host: "LOCALHOST", localHostName: "Mac"))
        XCTAssertTrue(OSC7.isLocal(host: "mac", localHostName: "Mac.local"))
        XCTAssertTrue(OSC7.isLocal(host: "Mac.local", localHostName: "mac"))
        XCTAssertTrue(OSC7.isLocal(host: "mac.lan", localHostName: "Mac.local"))
        XCTAssertFalse(OSC7.isLocal(host: "server", localHostName: "Mac.local"))
        XCTAssertFalse(OSC7.isLocal(host: "server.example", localHostName: ""))
    }
}
