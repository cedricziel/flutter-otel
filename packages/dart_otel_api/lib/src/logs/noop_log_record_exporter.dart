import '../common/export_result.dart';
import '../resource/otel_resource.dart';
import 'log_record.dart';
import 'log_record_exporter.dart';

/// A [LogRecordExporter] that discards every record and always reports
/// success, without making any I/O calls.
///
/// Used when the SDK is configured with `enabled: false`, so application
/// code can call logging APIs unconditionally in every build without ever
/// producing network traffic.
class NoopLogRecordExporter implements LogRecordExporter {
  const NoopLogRecordExporter();

  @override
  Future<ExportResult> export(
    List<LogRecord> records,
    OTelResource resource,
  ) async =>
      const ExportResult.success();

  @override
  Future<void> shutdown() async {}
}
