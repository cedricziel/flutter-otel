import Foundation

public struct NativeRecordEvent {
    public let name: String
    public let timestamp: Date
    public let attributes: [String: Any]

    public init(name: String, timestamp: Date, attributes: [String: Any] = [:]) {
        self.name = name
        self.timestamp = timestamp
        self.attributes = attributes
    }
}

public enum NativeSpanKind: String {
    case internalKind = "internal"
    case server
    case client
    case producer
    case consumer
}

public enum NativeStatusCode: String {
    case unset
    case ok
    case error
}

public enum NativeLogSeverity: String {
    case trace
    case debug
    case info
    case warn
    case error
    case fatal
}

/// The only entry point native instrumentation (cold-start, crash capture,
/// background tasks, native networking — none implemented yet) will call
/// to record a finished span or log record. Defaults a new record's trace
/// context onto whatever [setTraceContext] last set, and tags it with
/// whatever [setSessionId] last set, unless the caller passes explicit
/// IDs/attributes.
public final class NativeTelemetryRecorder {
    private let queue: RecordQueue
    private let lock = NSLock()
    private var currentTraceId: String?
    private var currentSpanId: String?
    private var currentSessionId: String?

    public init(queue: RecordQueue) {
        self.queue = queue
    }

    public func setTraceContext(traceId: String, spanId: String) {
        lock.lock(); defer { lock.unlock() }
        currentTraceId = traceId
        currentSpanId = spanId
    }

    public func clearTraceContext() {
        lock.lock(); defer { lock.unlock() }
        currentTraceId = nil
        currentSpanId = nil
    }

    public func setSessionId(_ sessionId: String) {
        lock.lock(); defer { lock.unlock() }
        currentSessionId = sessionId
    }

    public func drainQueue() -> RecordQueue.DrainResult {
        queue.drain()
    }

    @discardableResult
    public func recordSpan(
        name: String,
        kind: NativeSpanKind = .internalKind,
        start: Date,
        end: Date,
        attributes: [String: Any] = [:],
        events: [NativeRecordEvent] = [],
        statusCode: NativeStatusCode = .unset,
        statusDescription: String? = nil,
        traceId explicitTraceId: String? = nil,
        spanId explicitSpanId: String? = nil,
        parentSpanId explicitParentSpanId: String? = nil
    ) -> (traceId: String, spanId: String) {
        lock.lock()
        let inheritedTraceId = currentTraceId
        let inheritedSpanId = currentSpanId
        let sessionId = currentSessionId
        lock.unlock()

        let traceId = explicitTraceId ?? inheritedTraceId ?? NativeId.generateTraceId()
        let spanId = explicitSpanId ?? NativeId.generateSpanId()
        let parentSpanId = explicitParentSpanId
            ?? (explicitTraceId == nil ? inheritedSpanId : nil)

        var mergedAttributes = attributes
        if let sessionId = sessionId, mergedAttributes["session.id"] == nil {
            mergedAttributes["session.id"] = sessionId
        }

        var record: [String: Any] = [
            "kind": "span",
            "name": name,
            "traceId": traceId,
            "spanId": spanId,
            "spanKind": kind.rawValue,
            "startTimeUnixNano": String(unixNano(start)),
            "endTimeUnixNano": String(unixNano(end)),
            "attributes": mergedAttributes,
            "events": events.map { event -> [String: Any] in
                [
                    "name": event.name,
                    "timeUnixNano": String(unixNano(event.timestamp)),
                    "attributes": event.attributes,
                ]
            },
            "statusCode": statusCode.rawValue,
            "scopeName": "flutter_otel_native",
            "scopeVersion": "0.1.0",
        ]
        if let parentSpanId = parentSpanId {
            record["parentSpanId"] = parentSpanId
        }
        if let statusDescription = statusDescription {
            record["statusDescription"] = statusDescription
        }

        queue.append(record)
        return (traceId, spanId)
    }

    public func recordLog(
        body: String,
        severity: NativeLogSeverity = .info,
        timestamp: Date = Date(),
        attributes: [String: Any] = [:]
    ) {
        lock.lock()
        let traceId = currentTraceId
        let spanId = currentSpanId
        let sessionId = currentSessionId
        lock.unlock()

        var mergedAttributes = attributes
        if let sessionId = sessionId, mergedAttributes["session.id"] == nil {
            mergedAttributes["session.id"] = sessionId
        }

        var record: [String: Any] = [
            "kind": "log",
            "timeUnixNano": String(unixNano(timestamp)),
            "severity": severity.rawValue,
            "body": body,
            "attributes": mergedAttributes,
        ]
        if let traceId = traceId {
            record["traceId"] = traceId
        }
        if let spanId = spanId {
            record["spanId"] = spanId
        }

        queue.append(record)
    }

    private func unixNano(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000_000_000)
    }
}
