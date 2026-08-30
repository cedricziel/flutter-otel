import 'dart:async';

import 'package:flutter_otel_api/flutter_otel_api.dart';

/// A [SpanExporter] test double that records every batch it receives and
/// can be configured to fail or to complete only when released, so tests
/// can assert on batching/timing behavior deterministically.
class FakeSpanExporter implements SpanExporter {
  final List<List<SpanData>> exportedBatches = [];
  final List<OTelResource> resources = [];
  int shutdownCallCount = 0;

  /// When set, every export attempt fails with this result instead of
  /// succeeding.
  ExportResult? nextResult;

  /// When non-null, each call to [export] waits on this completer before
  /// resolving, letting tests observe in-flight state.
  Completer<void>? gate;

  Completer<void> _nextExport = Completer<void>();

  /// Completes the next time [export] is called, then resets for the call
  /// after that. Lets a test await the processor's own automatic
  /// flush-on-threshold/timer export instead of forcing one with
  /// `forceFlush()`, so the automatic path is actually exercised.
  Future<void> get nextExport => _nextExport.future;

  @override
  Future<ExportResult> export(
    List<SpanData> spans,
    OTelResource resource,
  ) async {
    if (gate != null) {
      await gate!.future;
    }
    exportedBatches.add(spans);
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

  /// All spans across every batch exported so far, in order.
  List<SpanData> get allSpans =>
      exportedBatches.expand((batch) => batch).toList();
}
