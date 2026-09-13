import 'span_data.dart';
import 'tracer.dart';

/// Vends [Tracer]s, mirroring `LoggerProvider`'s shape for the traces
/// signal.
abstract class TracerProvider {
  /// Returns a [Tracer] for the given instrumentation scope.
  Tracer getTracer({String name = 'flutter_otel', String? version});

  /// Feeds an externally-produced (already-finished) span directly into
  /// the processor pipeline — e.g. one recorded natively before Dart ran.
  void ingestSpan(SpanData span);

  /// Forces any buffered spans to be exported now.
  Future<void> forceFlush();

  /// Flushes and releases the underlying pipeline.
  Future<void> shutdown();
}

/// No-op [TracerProvider] used when tracing has no backing SDK. Always
/// returns a [NoopTracer]; flush/shutdown/ingestSpan are instant no-ops.
class NoopTracerProvider implements TracerProvider {
  const NoopTracerProvider();

  @override
  Tracer getTracer({String name = 'flutter_otel', String? version}) =>
      NoopTracer(name);

  @override
  void ingestSpan(SpanData span) {}

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
