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

    func testAppendAbandonsTheWriteWhenTheExistingQueueFileCannotBeRead() throws {
        let queue = RecordQueue(fileURL: fileURL, maxRecords: 10)
        queue.append(["kind": "log", "body": "original"])

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        }

        // The file can't be read while it's unreadable, so this append must
        // be abandoned rather than rewriting the file with just this line.
        queue.append(["kind": "log", "body": "should be dropped"])

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        let result = queue.drain()

        XCTAssertEqual(result.lines.count, 1)
        XCTAssertTrue(result.lines[0].contains("original"))
    }

    func testDrainKeepsTheDropCounterAndRecordsWhenClearingFails() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("record_queue_write_fail_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let restrictedFileURL = dir.appendingPathComponent("queue.ndjson")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }

        let queue = RecordQueue(fileURL: restrictedFileURL, maxRecords: 1)
        queue.append(["kind": "log", "body": "one"])
        queue.append(["kind": "log", "body": "two"])

        // Remove write permission on the directory so the atomic clear
        // write inside drain() fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)

        let firstDrain = queue.drain()
        XCTAssertEqual(firstDrain.lines.count, 1)
        XCTAssertEqual(firstDrain.droppedSinceLastDrain, 1)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)

        let secondDrain = queue.drain()
        XCTAssertEqual(
            secondDrain.droppedSinceLastDrain, 1,
            "the drop count should survive a failed clear rather than being reset"
        )
        XCTAssertEqual(
            secondDrain.lines.count, 1,
            "the record should still be there since the earlier clear never took effect"
        )
    }
}
