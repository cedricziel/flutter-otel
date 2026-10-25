import 'dart:async';

import 'package:dart_otel_api/dart_otel_api.dart';

/// A [MetricExporter] test double that records every batch it receives.
class FakeMetricExporter implements MetricExporter {
  final List<List<MetricData>> exportedBatches = [];
  final List<OTelResource> resources = [];
  int shutdownCallCount = 0;

  /// When set, every export attempt returns this result instead of success.
  ExportResult? nextResult;

  /// When non-null, each call to [export] waits on this completer first.
  Completer<void>? gate;

  Completer<void> _nextExport = Completer<void>();

  /// Completes the next time [export] is called, so a test can await the
  /// reader's own timer-driven export.
  Future<void> get nextExport => _nextExport.future;

  @override
  Future<ExportResult> export(
    List<MetricData> metrics,
    OTelResource resource,
  ) async {
    if (gate != null) {
      await gate!.future;
    }
    exportedBatches.add(metrics);
    resources.add(resource);
    final completer = _nextExport;
    _nextExport = Completer<void>();
    if (!completer.isCompleted) completer.complete();
    return nextResult ?? const ExportResult.success();
  }

  @override
  Future<void> shutdown() async {
    shutdownCallCount++;
  }
}
