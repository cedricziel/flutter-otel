import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:meta/meta.dart';

/// A [SpanProcessor] that buffers finished spans and exports them in
/// batches, either when [maxExportBatchSize] is reached or every
/// [scheduledDelay] on a periodic timer — whichever comes first. Buffered
/// spans beyond [maxQueueSize] are dropped (oldest first) to bound memory
/// use.
///
/// Export failures are swallowed and reported to [stderr]; they never
/// propagate into application code.
class BatchSpanProcessor implements SpanProcessor {
  BatchSpanProcessor(
    this.exporter,
    this.resource, {
    this.maxQueueSize = 2048,
    this.maxExportBatchSize = 512,
    this.scheduledDelay = const Duration(seconds: 5),
  }) {
    if (maxQueueSize <= 0) {
      throw ArgumentError.value(
        maxQueueSize,
        'maxQueueSize',
        'Must be greater than 0.',
      );
    }
    if (maxExportBatchSize <= 0) {
      throw ArgumentError.value(
        maxExportBatchSize,
        'maxExportBatchSize',
        'Must be greater than 0.',
      );
    }
    if (scheduledDelay <= Duration.zero) {
      throw ArgumentError.value(
        scheduledDelay,
        'scheduledDelay',
        'Must be greater than Duration.zero.',
      );
    }
    _timer = Timer.periodic(scheduledDelay, (_) => unawaited(_flushBatches()));
  }

  final SpanExporter exporter;
  final OTelResource resource;
  final int maxQueueSize;
  final int maxExportBatchSize;
  final Duration scheduledDelay;

  final Queue<SpanData> _queue = Queue<SpanData>();
  Timer? _timer;
  bool _shutdown = false;
  Future<void>? _flushInProgress;

  /// The number of spans currently buffered, awaiting export. Exposed for
  /// tests.
  @visibleForTesting
  int get queueLength => _queue.length;

  @override
  void onEnd(SpanData span) {
    if (_shutdown) return;
    if (_queue.length >= maxQueueSize) {
      _queue.removeFirst();
    }
    _queue.add(span);
    if (_queue.length >= maxExportBatchSize) {
      unawaited(_flushBatches());
    }
  }

  Future<void> _flushBatches() {
    final inProgress = _flushInProgress;
    if (inProgress != null) return inProgress;
    final future = _drainQueue();
    _flushInProgress = future;
    return future.whenComplete(() => _flushInProgress = null);
  }

  Future<void> _drainQueue() async {
    while (_queue.isNotEmpty) {
      final batchSize = _queue.length < maxExportBatchSize
          ? _queue.length
          : maxExportBatchSize;
      final batch = List<SpanData>.generate(
        batchSize,
        (_) => _queue.removeFirst(),
      );
      try {
        final result = await exporter.export(batch, resource);
        if (!result.success) {
          stderr.writeln(
            'flutter_otel: batch span export failed: ${result.error}',
          );
        }
      } catch (e, stackTrace) {
        stderr.writeln(
          'flutter_otel: batch span export threw: $e\n$stackTrace',
        );
      }
    }
  }

  @override
  Future<void> forceFlush() => _flushBatches();

  @override
  Future<void> shutdown() async {
    _shutdown = true;
    _timer?.cancel();
    _timer = null;
    await _flushBatches();
    await exporter.shutdown();
  }
}
