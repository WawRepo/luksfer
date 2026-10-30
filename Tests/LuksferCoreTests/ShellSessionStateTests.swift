import XCTest
@testable import LuksferCore

final class ShellSessionStateTests: XCTestCase {
    private let a = URL(fileURLWithPath: "/tmp/a", isDirectory: true)
    private let b = URL(fileURLWithPath: "/tmp/b b", isDirectory: true)
    private let c = URL(fileURLWithPath: "/tmp/c", isDirectory: true)

    /// A shell that started in `a` and waits at its prompt.
    private func idleInA() -> ShellSessionState {
        var s = ShellSessionState()
        XCTAssertEqual(s.reported(folder: a), .user(a))
        XCTAssertNil(s.received(.prompt))
        return s
    }

    func testIdleAfterPromptOnly() {
        var s = ShellSessionState()
        XCTAssertFalse(s.isIdle)
        XCTAssertEqual(s.request(b), .busy)
        _ = s.received(.prompt)
        XCTAssertTrue(s.isIdle)
        _ = s.received(.exec)
        XCTAssertFalse(s.isIdle)
        _ = s.received(.promptTyped)
        XCTAssertFalse(s.isIdle)
    }

    func testUserInputClearsIdle() {
        var s = idleInA()
        s.userInput()
        XCTAssertFalse(s.isIdle)
        XCTAssertEqual(s.request(b), .busy)
        _ = s.received(.prompt)
        XCTAssertTrue(s.isIdle)
    }

    func testSendsCdWhenIdleAndReportsItAsOwn() {
        var s = idleInA()
        XCTAssertEqual(s.request(b), .send(ZshIntegration.followKeys(to: "/tmp/b b")))
        XCTAssertFalse(s.isIdle, "the move Luksfer sent is not user input, but the shell is busy now")
        _ = s.received(.exec)
        XCTAssertEqual(s.reported(folder: b), .own(b))
        XCTAssertNil(s.received(.prompt))
        XCTAssertTrue(s.isIdle)
        XCTAssertEqual(s.folder?.path, "/tmp/b b")
    }

    func testSameFolderIsNotSent() {
        var s = idleInA()
        XCTAssertEqual(s.request(a), .alreadyThere)
        XCTAssertEqual(s.request(URL(fileURLWithPath: "/tmp/a/")), .alreadyThere)
        XCTAssertTrue(s.isIdle)
    }

    func testRepeatsAreDropped() {
        var s = idleInA()
        XCTAssertNil(s.reported(folder: a))
        XCTAssertNil(s.reported(folder: URL(fileURLWithPath: "/tmp/a/")))
        XCTAssertEqual(s.reported(folder: c), .user(c))
        XCTAssertNil(s.reported(folder: c))
    }

    func testRequestWhileOwnCdRunsIsQueued() {
        var s = idleInA()
        guard case .send = s.request(b) else { return XCTFail("not sent") }
        XCTAssertEqual(s.request(c), .queued)
        XCTAssertEqual(s.reported(folder: b), .own(b))
        XCTAssertEqual(s.received(.prompt), ZshIntegration.followKeys(to: "/tmp/c"))
        XCTAssertFalse(s.isIdle)
        XCTAssertEqual(s.reported(folder: c), .own(c))
        XCTAssertNil(s.received(.prompt))
        XCTAssertTrue(s.isIdle)
    }

    func testQueueGoesBackToTheFolderInFlight() {
        var s = idleInA()
        _ = s.request(b)
        XCTAssertEqual(s.request(c), .queued)
        XCTAssertEqual(s.request(b), .alreadyThere)
        _ = s.reported(folder: b)
        XCTAssertNil(s.received(.prompt))
        XCTAssertTrue(s.isIdle)
    }

    func testUserInputDropsTheQueue() {
        var s = idleInA()
        _ = s.request(b)
        _ = s.request(c)
        s.userInput()
        _ = s.reported(folder: b)
        XCTAssertNil(s.received(.prompt))
    }

    func testTypedAheadPromptDropsTheQueue() {
        var s = idleInA()
        _ = s.request(b)
        _ = s.request(c)
        XCTAssertNil(s.received(.promptTyped))
        XCTAssertFalse(s.isIdle)
        XCTAssertEqual(s.request(c), .busy)
    }

    func testUserCdIsReportedAsUser() {
        var s = idleInA()
        s.userInput()
        _ = s.received(.exec)
        XCTAssertEqual(s.reported(folder: c), .user(c))
    }

    func testReset() {
        var s = idleInA()
        s.reset()
        XCTAssertEqual(s, ShellSessionState())
        XCTAssertEqual(s.reported(folder: a), .user(a))
    }
}
