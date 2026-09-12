import Flutter
import NativeTelemetryCore

public class FlutterOtelNativePlugin: NSObject, FlutterPlugin {
    private let recorder: NativeTelemetryRecorder

    override public init() {
        let directory = FlutterOtelNativePlugin.queueDirectory()
        let queue = RecordQueue(fileURL: directory.appendingPathComponent("flutter_otel_native_queue.ndjson"))
        recorder = NativeTelemetryRecorder(queue: queue)
        super.init()
    }

    private static func queueDirectory() -> URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_otel_native", binaryMessenger: registrar.messenger())
        let instance = FlutterOtelNativePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "drainQueue":
            let drainResult = recorder.drainQueue()
            result([
                "records": drainResult.lines,
                "droppedSinceLastDrain": drainResult.droppedSinceLastDrain,
            ])
        case "setSessionId":
            guard let args = call.arguments as? [String: Any],
                  let sessionId = args["sessionId"] as? String
            else {
                result(FlutterError(code: "invalid_arguments", message: "sessionId is required", details: nil))
                return
            }
            recorder.setSessionId(sessionId)
            result(nil)
        case "setCurrentTraceContext":
            guard let args = call.arguments as? [String: Any],
                  let traceId = args["traceId"] as? String,
                  let spanId = args["spanId"] as? String
            else {
                result(FlutterError(code: "invalid_arguments", message: "traceId and spanId are required", details: nil))
                return
            }
            recorder.setTraceContext(traceId: traceId, spanId: spanId)
            result(nil)
        case "clearCurrentTraceContext":
            recorder.clearTraceContext()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
