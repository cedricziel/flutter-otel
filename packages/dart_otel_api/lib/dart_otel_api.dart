/// Platform-agnostic OpenTelemetry core: [OTelResource], the logs signal
/// contracts (implemented), the traces signal contracts (implemented,
/// including [Span]-based trace-to-log correlation and W3C trace-context
/// propagation helpers), and a minimal metrics stub (for later).
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
export 'src/trace/http_header_attributes.dart';
export 'src/trace/noop_span_exporter.dart';
export 'src/trace/span.dart';
export 'src/trace/span_context.dart';
export 'src/trace/span_data.dart';
export 'src/trace/span_event.dart';
export 'src/trace/span_exporter.dart';
export 'src/trace/span_kind.dart';
export 'src/trace/span_link.dart';
export 'src/trace/span_processor.dart';
export 'src/trace/status_code.dart';
export 'src/trace/tracer.dart';
export 'src/trace/tracer_provider.dart';
export 'src/trace/w3c_trace_context.dart';
