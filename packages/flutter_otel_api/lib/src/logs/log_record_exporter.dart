import '../common/export_result.dart';
import '../resource/otel_resource.dart';
import 'log_record.dart';

/// Sends batches of [LogRecord]s somewhere: a collector over OTLP/HTTP, a
/// dev-console printer, or a no-op sink.
///
/// Implementations must never throw out of [export]; report failures via a
/// failed [ExportResult] instead so processors can degrade gracefully.
abstract class LogRecordExporter {
  /// Exports [records], attributing them to [resource]. Never throws.
  Future<ExportResult> export(List<LogRecord> records, OTelResource resource);

  /// Releases any resources (e.g. an owned HTTP client) held by this
  /// exporter.
  Future<void> shutdown();
}
