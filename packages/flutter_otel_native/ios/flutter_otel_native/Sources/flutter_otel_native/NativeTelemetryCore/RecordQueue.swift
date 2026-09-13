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

            guard case let .success(existingLines) = readLinesLocked() else {
                // The existing queue file couldn't be read (as opposed to
                // simply not existing yet). Abandon this append rather than
                // rewrite the file with just the new line, which would
                // silently truncate away whatever was already queued.
                return
            }

            var lines = existingLines
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
    /// drain, then clears both — but only resets the drop counter once the
    /// clearing write actually succeeds, so a failed clear doesn't also
    /// erase the record that a drop occurred.
    public func drain() -> DrainResult {
        ioQueue.sync {
            let lines: [String]
            switch readLinesLocked() {
            case let .success(readLines):
                lines = readLines
            case .failure:
                lines = []
            }
            let dropped = droppedSinceLastDrain
            if writeLinesLocked([]) {
                droppedSinceLastDrain = 0
            }
            return DrainResult(lines: lines, droppedSinceLastDrain: dropped)
        }
    }

    /// Reads the queue file's lines. A missing file is treated as an empty
    /// queue (`.success([])`); any other read failure (permissions, a
    /// corrupt or undecodable file, and similar) is reported as `.failure`
    /// so callers can tell it apart from "nothing queued yet".
    private func readLinesLocked() -> Result<[String], Error> {
        do {
            let data = try Data(contentsOf: fileURL)
            guard let contents = String(data: data, encoding: .utf8) else {
                return .failure(CocoaError(.fileReadCorruptFile))
            }
            if contents.isEmpty {
                return .success([])
            }
            return .success(contents.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .success([])
        } catch {
            return .failure(error)
        }
    }

    /// Writes [lines] to the queue file, returning whether the write
    /// succeeded.
    @discardableResult
    private func writeLinesLocked(_ lines: [String]) -> Bool {
        let contents = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        do {
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
