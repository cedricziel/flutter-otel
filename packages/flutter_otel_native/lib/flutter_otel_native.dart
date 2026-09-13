/// Dart-side bridge to native (iOS/macOS) telemetry recorded via
/// flutter_otel_native's Swift plugin: draining its on-disk queue and
/// forwarding records into an existing TracerProvider/LoggerProvider
/// pipeline, plus trace-context/session handoff primitives.
library;

export 'src/native_record_codec.dart';
export 'src/native_telemetry_bridge.dart';
