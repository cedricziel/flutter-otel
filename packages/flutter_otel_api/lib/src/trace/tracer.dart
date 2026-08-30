import 'span.dart';
import 'span_context.dart';
import 'span_kind.dart';
import 'status_code.dart';

/// Creates and starts [Span]s for one instrumentation scope.
abstract class Tracer {
  /// The instrumentation scope name this tracer was obtained for.
  String get name;

  /// Starts (but does not activate) a new [Span].
  ///
  /// The parent is resolved by concrete implementations as: an explicit
  /// [parentContext], then the ambient [Span.current], then no parent (a
  /// root span). The returned span is not made [Span.current] — use
  /// [startActiveSpan] for that.
  Span startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    SpanContext? parentContext,
  });

  /// Starts a span, makes it [Span.current] for the duration of [body],
  /// ends it when [body] completes (recording the exception and setting an
  /// error status if [body] throws, then rethrowing), and returns [body]'s
  /// result.
  Future<T> startActiveSpan<T>(
    String name,
    Future<T> Function(Span span) body, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
  });
}

/// No-op [Tracer] used when tracing has no backing SDK (e.g. before
/// `OTelSdk.initialize`, or when a caller works against [flutter_otel_api]
/// standalone). Spans it produces carry an invalid, all-zero
/// [SpanContext] and record nothing.
class NoopTracer implements Tracer {
  const NoopTracer(this.name);

  @override
  final String name;

  @override
  Span startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    SpanContext? parentContext,
  }) =>
      _NoopSpan(name);

  @override
  Future<T> startActiveSpan<T>(
    String name,
    Future<T> Function(Span span) body, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
  }) {
    final span = _NoopSpan(name);
    return Span.runWithSpan(span, () => body(span));
  }
}

class _NoopSpan implements Span {
  _NoopSpan(this.name);

  @override
  final String name;

  @override
  final SpanContext spanContext = const SpanContext(
    traceId: '00000000000000000000000000000000', // 32 zero chars
    spanId: '0000000000000000', // 16 zero chars
  );

  @override
  bool get isRecording => false;

  @override
  void setAttribute(String key, Object? value) {}

  @override
  void setAttributes(Map<String, Object?> attributes) {}

  @override
  void addEvent(
    String name, {
    Map<String, Object?>? attributes,
    DateTime? timestamp,
  }) {}

  @override
  void setStatus(StatusCode code, {String? description}) {}

  @override
  void recordException(
    Object exception, {
    StackTrace? stackTrace,
    Map<String, Object?>? attributes,
  }) {}

  @override
  void end([DateTime? endTime]) {}
}
