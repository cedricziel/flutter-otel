import 'package:dart_otel_api/dart_otel_api.dart';

/// A [LogRecordProcessor] that forwards to several processors, so one
/// logger provider can feed more than one pipeline (e.g. an OTLP batch
/// exporter and a local console sink).
///
/// A processor that throws never prevents the others from being reached.
class MultiLogRecordProcessor implements LogRecordProcessor {
  MultiLogRecordProcessor(List<LogRecordProcessor> processors)
      : _processors = List.unmodifiable(processors);

  final List<LogRecordProcessor> _processors;

  @override
  void onEmit(LogRecord record) {
    for (final processor in _processors) {
      try {
        processor.onEmit(record);
      } catch (_) {}
    }
  }

  @override
  Future<void> forceFlush() => _forEach((p) => p.forceFlush());

  @override
  Future<void> shutdown() => _forEach((p) => p.shutdown());

  Future<void> _forEach(Future<void> Function(LogRecordProcessor) action) =>
      Future.wait(
        _processors.map((p) async {
          try {
            await action(p);
          } catch (_) {}
        }),
      );
}
