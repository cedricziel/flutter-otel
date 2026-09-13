import 'dart:async';
import 'dart:io';

import 'package:flutter_otel_api/flutter_otel_api.dart';

/// A [LogRecordProcessor] that exports every record immediately, one at a
/// time. Intended for development and tests, where seeing a log show up
/// right away matters more than batching efficiency.
class SimpleLogRecordProcessor implements LogRecordProcessor {
  SimpleLogRecordProcessor(this.exporter, this.resource);

  final LogRecordExporter exporter;
  final OTelResource resource;

  final List<Future<void>> _pending = [];
  bool _shutdown = false;

  @override
  void onEmit(LogRecord record) {
    if (_shutdown) return;
    final future = _exportSafely([record]);
    _pending.add(future);
    unawaited(future.whenComplete(() => _pending.remove(future)));
  }

  Future<void> _exportSafely(List<LogRecord> records) async {
    try {
      final result = await exporter.export(records, resource);
      if (!result.success) {
        stderr.writeln('flutter_otel: log export failed: ${result.error}');
      }
    } catch (e, stackTrace) {
      stderr.writeln('flutter_otel: log export threw: $e\n$stackTrace');
    }
  }

  @override
  Future<void> forceFlush() => Future.wait(List<Future<void>>.of(_pending));

  @override
  Future<void> shutdown() async {
    _shutdown = true;
    await forceFlush();
    await exporter.shutdown();
  }
}
