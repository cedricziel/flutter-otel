import '../logs/log_record.dart' show defaultInstrumentationScopeName;
import 'span_context.dart';
import 'span_event.dart';
import 'span_kind.dart';
import 'span_link.dart';
import 'status_code.dart';

/// Immutable snapshot of a finished span, handed to exporters — analogous
/// to `LogRecord` for the logs signal.
class SpanData {
  SpanData({
    required this.name,
    required this.spanContext,
    this.parentSpanId,
    this.kind = SpanKind.internal,
    required this.startTime,
    required this.endTime,
    Map<String, Object?> attributes = const {},
    List<SpanEvent> events = const [],
    List<SpanLink> links = const [],
    this.statusCode = StatusCode.unset,
    this.statusDescription,
    this.scopeName = defaultInstrumentationScopeName,
    this.scopeVersion,
  })  : attributes = Map.unmodifiable(attributes),
        events = List.unmodifiable(events),
        links = List.unmodifiable(links);

  /// The span's name.
  final String name;

  /// This span's own trace/span IDs.
  final SpanContext spanContext;

  /// The hex-encoded span ID of this span's parent, or `null` for a root
  /// span.
  final String? parentSpanId;

  /// The span's kind.
  final SpanKind kind;

  /// When the span started.
  final DateTime startTime;

  /// When the span ended.
  final DateTime endTime;

  /// Structured attributes attached to this span. Read-only.
  final Map<String, Object?> attributes;

  /// Timestamped events recorded during the span's lifetime. Read-only.
  final List<SpanEvent> events;

  /// Links to other causally related spans, typically in a different
  /// trace. Read-only.
  final List<SpanLink> links;

  /// The final status of the operation this span represents.
  final StatusCode statusCode;

  /// A human-readable description of [statusCode], if any.
  final String? statusDescription;

  /// The name of the instrumentation scope (tracer) that produced this
  /// span.
  final String scopeName;

  /// The version of the instrumentation scope (tracer) that produced this
  /// span, if any.
  final String? scopeVersion;

  @override
  String toString() => 'SpanData(name: $name, spanContext: $spanContext, '
      'statusCode: $statusCode)';
}
