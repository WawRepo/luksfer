import XCTest
@testable import LuksferCore

final class TestSwitchesTests: XCTestCase {
    func testSwitchesCountOnlyInASelfTestMode() {
        let name = "LUKSFER_TRASH_DIR"
        XCTAssertNil(TestSwitches.selfTestOnly(name, in: [name: "/box"]))
        XCTAssertNil(TestSwitches.selfTestOnly(name, in: [name: "/box", "LUKSFER_SELFTEST": ""]))
        XCTAssertNil(TestSwitches.selfTestOnly(name, in: [name: "/box", "LUKSFER_SELFTEST": "yes"]))
        for mode in ["1", "restore", "opened"] {
            XCTAssertEqual(TestSwitches.selfTestOnly(name, in: [name: "/box", "LUKSFER_SELFTEST": mode]), "/box", mode)
            XCTAssertNil(TestSwitches.selfTestOnly(name, in: ["LUKSFER_SELFTEST": mode]), mode)
        }
    }
}
