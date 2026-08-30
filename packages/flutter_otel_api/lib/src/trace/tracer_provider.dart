import 'tracer.dart';

/// Vends [Tracer]s, mirroring [LoggerProvider]'s shape for the future
/// traces signal.
abstract class TracerProvider {
  /// Returns a [Tracer] for the given instrumentation scope.
  Tracer getTracer({String name = 'flutter_otel', String? version});

  /// Forces any buffered spans to be exported now.
  Future<void> forceFlush();

  /// Flushes and releases the underlying pipeline.
  Future<void> shutdown();
}

/// No-op [TracerProvider] used until a real tracing SDK implementation
/// exists. Always returns a [NoopTracer]; flush/shutdown are instant no-ops.
class NoopTracerProvider implements TracerProvider {
  const NoopTracerProvider();

  @override
  Tracer getTracer({String name = 'flutter_otel', String? version}) =>
      NoopTracer(name);

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
