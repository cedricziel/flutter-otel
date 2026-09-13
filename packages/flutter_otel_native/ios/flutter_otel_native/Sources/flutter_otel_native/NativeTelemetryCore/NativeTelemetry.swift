import Foundation

/// The single, process-wide entry point for native telemetry: owns the
/// on-disk queue location and the one shared `NativeTelemetryRecorder`
/// instance, so every call site in an app — the Flutter plugin's channel
/// handlers, and future native instrumentation call sites not built yet —
/// share one queue and one in-memory trace/session context instead of
/// each silently constructing their own and losing each other's data.
public enum NativeTelemetry {
    public static let shared: NativeTelemetryRecorder = {
        let directory = queueDirectory()
        let queue = RecordQueue(fileURL: directory.appendingPathComponent("flutter_otel_native_queue.ndjson"))
        return NativeTelemetryRecorder(queue: queue)
    }()

    private static func queueDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let bundleId = Bundle.main.bundleIdentifier ?? "flutter_otel_native"
        let directory = base.appendingPathComponent(bundleId, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
