import Foundation

/// Appends telemetry records as NDJSON lines to an on-disk queue file and
/// performs an atomic drain-and-clear, all serialized on one internal
/// dispatch queue so it's safe to call from any thread.
public final class RecordQueue {
    public struct DrainResult {
        public let lines: [String]
        public let droppedSinceLastDrain: Int
    }

    private let fileURL: URL
    private let maxRecords: Int
    private let ioQueue = DispatchQueue(label: "flutter_otel_native.record_queue")
    private var droppedSinceLastDrain = 0

    public init(fileURL: URL, maxRecords: Int = 2048) {
        self.fileURL = fileURL
        self.maxRecords = maxRecords
    }

    /// Appends [record] to the queue. Silently drops it (never throws) if
    /// it isn't a valid JSON object — a caller bug in a future
    /// instrumentation spec shouldn't be able to crash the app.
    public func append(_ record: [String: Any]) {
        ioQueue.sync {
            guard JSONSerialization.isValidJSONObject(record),
                  let data = try? JSONSerialization.data(withJSONObject: record),
                  let line = String(data: data, encoding: .utf8)
            else {
                return
            }

            var lines = readLinesLocked()
            lines.append(line)
            if lines.count > maxRecords {
                let overflow = lines.count - maxRecords
                lines.removeFirst(overflow)
                droppedSinceLastDrain += overflow
            }
            writeLinesLocked(lines)
        }
    }

    /// Returns every queued line and the drop count since the previous
    /// drain, then clears both.
    public func drain() -> DrainResult {
        ioQueue.sync {
            let lines = readLinesLocked()
            writeLinesLocked([])
            let dropped = droppedSinceLastDrain
            droppedSinceLastDrain = 0
            return DrainResult(lines: lines, droppedSinceLastDrain: dropped)
        }
    }

    private func readLinesLocked() -> [String] {
        guard let data = try? Data(contentsOf: fileURL),
              let contents = String(data: data, encoding: .utf8),
              !contents.isEmpty
        else {
            return []
        }
        return contents.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private func writeLinesLocked(_ lines: [String]) {
        let contents = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
