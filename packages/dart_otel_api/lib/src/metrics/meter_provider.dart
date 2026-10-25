import 'meter.dart';

/// Vends [Meter]s, mirroring `LoggerProvider`'s shape for the metrics
/// signal.
abstract class MeterProvider {
  /// Returns a [Meter] for the given instrumentation scope.
  Meter getMeter({String name = 'flutter_otel', String? version});

  /// Forces any buffered metric data points to be exported now.
  Future<void> forceFlush();

  /// Flushes and releases the underlying pipeline.
  Future<void> shutdown();
}

/// No-op [MeterProvider] used when metrics have no backing SDK. Always
/// returns a [NoopMeter]; flush/shutdown are instant no-ops.
class NoopMeterProvider implements MeterProvider {
  const NoopMeterProvider();

  @override
  Meter getMeter({String name = 'flutter_otel', String? version}) =>
      NoopMeter(name);

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
