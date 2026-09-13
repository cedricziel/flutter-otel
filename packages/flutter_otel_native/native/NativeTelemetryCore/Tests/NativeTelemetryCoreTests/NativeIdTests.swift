@testable import NativeTelemetryCore
import XCTest

final class NativeIdTests: XCTestCase {
    func testTraceIdIsThirtyTwoLowercaseHexCharacters() {
        let traceId = NativeId.generateTraceId()

        XCTAssertEqual(traceId.count, 32)
        XCTAssertNotNil(traceId.range(of: "^[0-9a-f]{32}$", options: .regularExpression))
    }

    func testSpanIdIsSixteenLowercaseHexCharacters() {
        let spanId = NativeId.generateSpanId()

        XCTAssertEqual(spanId.count, 16)
        XCTAssertNotNil(spanId.range(of: "^[0-9a-f]{16}$", options: .regularExpression))
    }

    func testGeneratesDistinctIdsAcrossCalls() {
        let first = NativeId.generateTraceId()
        let second = NativeId.generateTraceId()

        XCTAssertNotEqual(first, second)
    }
}
