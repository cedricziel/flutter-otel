@testable import NativeTelemetryCore
import XCTest

final class NativeTelemetryRecorderTests: XCTestCase {
    private var fileURL: URL!
    private var queue: RecordQueue!
    private var recorder: NativeTelemetryRecorder!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder_test_\(UUID().uuidString).ndjson")
        queue = RecordQueue(fileURL: fileURL, maxRecords: 10)
        recorder = NativeTelemetryRecorder(queue: queue)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    private func decodeLastRecord() throws -> [String: Any] {
        let result = queue.drain()
        let line = try XCTUnwrap(result.lines.last)
        let data = try XCTUnwrap(line.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testRecordSpanWithNoContextGeneratesARootTraceAndSpanId() throws {
        let ids = recorder.recordSpan(name: "op", start: Date(), end: Date())

        XCTAssertEqual(ids.traceId.count, 32)
        XCTAssertEqual(ids.spanId.count, 16)

        let json = try decodeLastRecord()
        XCTAssertEqual(json["kind"] as? String, "span")
        XCTAssertEqual(json["name"] as? String, "op")
        XCTAssertEqual(json["traceId"] as? String, ids.traceId)
        XCTAssertEqual(json["spanId"] as? String, ids.spanId)
        XCTAssertNil(json["parentSpanId"])
        XCTAssertEqual(json["spanKind"] as? String, "internal")
        XCTAssertEqual(json["statusCode"] as? String, "unset")
        XCTAssertEqual(json["scopeName"] as? String, "flutter_otel_native")
    }

    func testRecordSpanAttachesAsAChildWhenTraceContextIsSet() throws {
        recorder.setTraceContext(traceId: "4bf92f3577b34da6a3ce929d0e0e4736", spanId: "00f067aa0ba902b7")

        let ids = recorder.recordSpan(name: "op", start: Date(), end: Date())

        XCTAssertEqual(ids.traceId, "4bf92f3577b34da6a3ce929d0e0e4736")
        XCTAssertNotEqual(ids.spanId, "00f067aa0ba902b7")

        let json = try decodeLastRecord()
        XCTAssertEqual(json["parentSpanId"] as? String, "00f067aa0ba902b7")
    }

    func testClearTraceContextStopsFurtherChildAttachment() throws {
        recorder.setTraceContext(traceId: "4bf92f3577b34da6a3ce929d0e0e4736", spanId: "00f067aa0ba902b7")
        recorder.clearTraceContext()

        let ids = recorder.recordSpan(name: "op", start: Date(), end: Date())

        XCTAssertNotEqual(ids.traceId, "4bf92f3577b34da6a3ce929d0e0e4736")
        let json = try decodeLastRecord()
        XCTAssertNil(json["parentSpanId"])
    }

    func testExplicitIdsOverrideInheritedContext() throws {
        recorder.setTraceContext(traceId: "4bf92f3577b34da6a3ce929d0e0e4736", spanId: "00f067aa0ba902b7")

        let ids = recorder.recordSpan(
            name: "op",
            start: Date(),
            end: Date(),
            traceId: "11111111111111111111111111111111",
            spanId: "2222222222222222"
        )

        XCTAssertEqual(ids.traceId, "11111111111111111111111111111111")
        XCTAssertEqual(ids.spanId, "2222222222222222")
        let json = try decodeLastRecord()
        XCTAssertNil(json["parentSpanId"])
    }

    func testExplicitParentSpanIdIsDroppedWithoutATraceIdOrInheritedContext() throws {
        let ids = recorder.recordSpan(
            name: "op",
            start: Date(),
            end: Date(),
            parentSpanId: "00f067aa0ba902b7"
        )

        let json = try decodeLastRecord()
        XCTAssertEqual(json["traceId"] as? String, ids.traceId)
        XCTAssertNotEqual(ids.traceId, "")
        XCTAssertNil(
            json["parentSpanId"],
            "a freshly generated trace can't already contain the given parent span"
        )
    }

    func testRecordSpanEncodesEventsAndStatus() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(0.05)
        let event = NativeRecordEvent(name: "retry", timestamp: start, attributes: ["attempt": 1])

        _ = recorder.recordSpan(
            name: "op",
            kind: .client,
            start: start,
            end: end,
            attributes: ["http.method": "GET"],
            events: [event],
            statusCode: .error,
            statusDescription: "timed out"
        )

        let json = try decodeLastRecord()
        XCTAssertEqual(json["spanKind"] as? String, "client")
        XCTAssertEqual(json["statusCode"] as? String, "error")
        XCTAssertEqual(json["statusDescription"] as? String, "timed out")
        let attributes = try XCTUnwrap(json["attributes"] as? [String: Any])
        XCTAssertEqual(attributes["http.method"] as? String, "GET")
        let events = try XCTUnwrap(json["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["name"] as? String, "retry")
    }

    func testRecordLogMergesSessionIdWhenSet() throws {
        recorder.setSessionId("session-123")

        recorder.recordLog(body: "hello")

        let json = try decodeLastRecord()
        XCTAssertEqual(json["kind"] as? String, "log")
        XCTAssertEqual(json["body"] as? String, "hello")
        let attributes = try XCTUnwrap(json["attributes"] as? [String: Any])
        XCTAssertEqual(attributes["session.id"] as? String, "session-123")
    }

    func testRecordLogCarriesTheActiveTraceContext() throws {
        recorder.setTraceContext(traceId: "4bf92f3577b34da6a3ce929d0e0e4736", spanId: "00f067aa0ba902b7")

        recorder.recordLog(body: "hello")

        let json = try decodeLastRecord()
        XCTAssertEqual(json["traceId"] as? String, "4bf92f3577b34da6a3ce929d0e0e4736")
        XCTAssertEqual(json["spanId"] as? String, "00f067aa0ba902b7")
    }

    func testRecordLogWithNoContextOmitsTraceFields() throws {
        recorder.recordLog(body: "hello")

        let json = try decodeLastRecord()
        XCTAssertNil(json["traceId"])
        XCTAssertNil(json["spanId"])
    }

    func testDrainQueuePassesThroughToTheUnderlyingQueue() {
        recorder.recordLog(body: "hello")

        let result = recorder.drainQueue()

        XCTAssertEqual(result.lines.count, 1)
    }
}
