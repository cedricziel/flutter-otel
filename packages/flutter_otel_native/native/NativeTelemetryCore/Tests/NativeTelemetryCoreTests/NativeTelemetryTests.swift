@testable import NativeTelemetryCore
import XCTest

final class NativeTelemetryTests: XCTestCase {
    func testSharedReturnsTheSameInstanceAcrossAccesses() {
        XCTAssertTrue(NativeTelemetry.shared === NativeTelemetry.shared)
    }

    func testSharedRecordsAndDrainsSuccessfully() {
        NativeTelemetry.shared.recordLog(body: "smoke test")

        let result = NativeTelemetry.shared.drainQueue()

        XCTAssertFalse(result.lines.isEmpty)
    }
}
