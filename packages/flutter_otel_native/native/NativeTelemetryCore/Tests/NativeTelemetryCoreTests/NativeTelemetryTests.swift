@testable import NativeTelemetryCore
import XCTest

final class NativeTelemetryTests: XCTestCase {
    func testSharedReturnsTheSameInstanceAcrossAccesses() {
        XCTAssertTrue(NativeTelemetry.shared === NativeTelemetry.shared)
    }

    func testSharedRecordsAndDrainsSuccessfully() {
        // NativeTelemetry.shared persists to an app-local file, so discard
        // whatever a previous run left behind before asserting on this run's
        // own record.
        _ = NativeTelemetry.shared.drainQueue()

        NativeTelemetry.shared.recordLog(body: "smoke test")

        let result = NativeTelemetry.shared.drainQueue()

        XCTAssertEqual(result.lines.count, 1)
        XCTAssertTrue(result.lines[0].contains("smoke test"))
    }
}
