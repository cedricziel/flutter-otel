import '../common/export_result.dart';
import '../resource/otel_resource.dart';
import 'span_data.dart';

/// Sends batches of [SpanData] somewhere: a collector over OTLP/HTTP, a
/// dev-console printer, or a no-op sink.
///
/// Implementations must never throw out of [export]; report failures via a
/// failed [ExportResult] instead so processors can degrade gracefully.
abstract class SpanExporter {
  /// Exports [spans], attributing them to [resource]. Never throws.
  Future<ExportResult> export(List<SpanData> spans, OTelResource resource);

  /// Releases any resources (e.g. an owned HTTP client) held by this
  /// exporter.
  Future<void> shutdown();
}
