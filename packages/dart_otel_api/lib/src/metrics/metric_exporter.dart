import '../common/export_result.dart';
import '../resource/otel_resource.dart';
import 'metric_data.dart';

/// Sends collected [MetricData] somewhere: a collector over OTLP/HTTP or a
/// no-op sink.
///
/// Implementations must never throw out of [export]; report failures via a
/// failed [ExportResult] instead.
abstract class MetricExporter {
  /// Exports [metrics], attributing them to [resource]. Never throws.
  Future<ExportResult> export(List<MetricData> metrics, OTelResource resource);

  /// Releases any resources (e.g. an owned HTTP client) held by this
  /// exporter.
  Future<void> shutdown();
}

/// [MetricExporter] that discards everything.
class NoopMetricExporter implements MetricExporter {
  const NoopMetricExporter();

  @override
  Future<ExportResult> export(
    List<MetricData> metrics,
    OTelResource resource,
  ) async =>
      const ExportResult.success();

  @override
  Future<void> shutdown() async {}
}
