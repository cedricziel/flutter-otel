import 'dart:async';

import 'package:flutter_otel_api/flutter_otel_api.dart';

/// A [LogRecordExporter] test double that records every batch it receives
/// and can be configured to fail or to complete only when released, so
/// tests can assert on batching/timing behavior deterministically.
class FakeLogRecordExporter implements LogRecordExporter {
  final List<List<LogRecord>> exportedBatches = [];
  final List<OTelResource> resources = [];
  int shutdownCallCount = 0;

  /// When set, every export attempt fails with this result instead of
  /// succeeding.
  ExportResult? nextResult;

  /// When non-null, each call to [export] waits on this completer before
  /// resolving, letting tests observe in-flight state.
  Completer<void>? gate;

  @override
  Future<ExportResult> export(
    List<LogRecord> records,
    OTelResource resource,
  ) async {
    if (gate != null) {
      await gate!.future;
    }
    exportedBatches.add(records);
    resources.add(resource);
    return nextResult ?? const ExportResult.success();
  }

  @override
  Future<void> shutdown() async {
    shutdownCallCount++;
  }

  /// All records across every batch exported so far, in order.
  List<LogRecord> get allRecords =>
      exportedBatches.expand((batch) => batch).toList();
}
