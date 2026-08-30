import '../common/export_result.dart';
import '../resource/otel_resource.dart';
import 'span_data.dart';
import 'span_exporter.dart';

/// A [SpanExporter] that discards every span and always reports success,
/// without making any I/O calls.
///
/// Used when the SDK is configured with `enabled: false`, so application
/// code can call tracing APIs unconditionally in every build without ever
/// producing network traffic.
class NoopSpanExporter implements SpanExporter {
  const NoopSpanExporter();

  @override
  Future<ExportResult> export(
    List<SpanData> spans,
    OTelResource resource,
  ) async =>
      const ExportResult.success();

  @override
  Future<void> shutdown() async {}
}
