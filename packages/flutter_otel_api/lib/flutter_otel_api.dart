/// Platform-agnostic OpenTelemetry core: [OTelResource], the logs signal
/// contracts (implemented), and minimal trace/metric stubs (for later).
///
/// Pure Dart — no Flutter, `http`, or `uuid` dependency — so it can be
/// depended on from any Dart target (mobile, desktop, web, server, CLI).
library;

export 'src/common/any_value_codec.dart';
export 'src/common/export_result.dart';
export 'src/logs/log_record.dart';
export 'src/logs/log_record_exporter.dart';
export 'src/logs/log_record_processor.dart';
export 'src/logs/log_severity.dart';
export 'src/logs/logger.dart';
export 'src/logs/logger_provider.dart';
export 'src/logs/noop_log_record_exporter.dart';
export 'src/metrics/meter.dart';
export 'src/metrics/meter_provider.dart';
export 'src/resource/otel_resource.dart';
export 'src/session/session_manager.dart';
export 'src/trace/tracer.dart';
export 'src/trace/tracer_provider.dart';
