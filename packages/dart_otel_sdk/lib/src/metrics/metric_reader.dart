import 'package:dart_otel_api/dart_otel_api.dart';

/// A source of the current cumulative state of every instrument.
abstract class MetricProducer {
  /// Snapshots all instruments that have data.
  List<MetricData> collect();
}

/// Pulls metrics from a [MetricProducer] and hands them on, typically to a
/// [MetricExporter].
abstract class MetricReader {
  /// Called once by the provider that this reader serves.
  void register(MetricProducer producer);

  /// Collects and exports now. Resolves once the attempt has finished,
  /// whether or not it succeeded.
  Future<void> forceFlush();

  /// Exports a final time and releases the underlying resources.
  Future<void> shutdown();
}
