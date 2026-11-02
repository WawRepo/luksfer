import XCTest
@testable import LuksferCore

final class VolumeSpaceTests: XCTestCase {
    func testOtherDisksReportZeroImportantSpace() {
        XCTAssertEqual(VolumeSpace.free(important: 0, plain: 128_000), 128_000)
    }

    func testStartupDiskCountsPurgeableSpace() {
        XCTAssertEqual(VolumeSpace.free(important: 3_000, plain: 2_900), 3_000)
    }

    func testOneNumberIsEnough() {
        XCTAssertEqual(VolumeSpace.free(important: nil, plain: 5), 5)
        XCTAssertEqual(VolumeSpace.free(important: 5, plain: nil), 5)
    }

    func testNoNumbersMeansUnknown() {
        XCTAssertNil(VolumeSpace.free(important: nil, plain: nil))
    }

    func testReadsARealDisk() {
        XCTAssertGreaterThan(VolumeSpace.free(at: URL(fileURLWithPath: "/")) ?? 0, 0)
    }
}
