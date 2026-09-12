@testable import NativeTelemetryCore
import XCTest

final class RecordQueueTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("record_queue_test_\(UUID().uuidString).ndjson")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    func testDrainReturnsAppendedRecordsAndClearsTheFile() {
        let queue = RecordQueue(fileURL: fileURL, maxRecords: 10)
        queue.append(["kind": "log", "body": "one"])
        queue.append(["kind": "log", "body": "two"])

        let result = queue.drain()

        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.droppedSinceLastDrain, 0)
        XCTAssertTrue(queue.drain().lines.isEmpty)
    }

    func testEvictsOldestRecordsPastTheCapAndReportsTheDropCount() {
        let queue = RecordQueue(fileURL: fileURL, maxRecords: 2)
        queue.append(["kind": "log", "body": "one"])
        queue.append(["kind": "log", "body": "two"])
        queue.append(["kind": "log", "body": "three"])

        let result = queue.drain()

        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.droppedSinceLastDrain, 1)
        XCTAssertFalse(result.lines.contains { $0.contains("\"one\"") })
    }

    func testSkipsRecordsThatArentValidJSONObjectsWithoutCrashing() {
        let queue = RecordQueue(fileURL: fileURL, maxRecords: 10)
        queue.append(["kind": "log", "body": "ok"])
        // NaN has no JSON representation; JSONSerialization rejects it, so
        // this append should be silently dropped rather than throwing.
        queue.append(["kind": "log", "value": Double.nan])

        let result = queue.drain()

        XCTAssertEqual(result.lines.count, 1)
    }

    func testDropCounterResetsAfterEachDrain() {
        let queue = RecordQueue(fileURL: fileURL, maxRecords: 1)
        queue.append(["kind": "log", "body": "one"])
        queue.append(["kind": "log", "body": "two"])
        _ = queue.drain()

        queue.append(["kind": "log", "body": "three"])
        let result = queue.drain()

        XCTAssertEqual(result.droppedSinceLastDrain, 0)
    }
}
