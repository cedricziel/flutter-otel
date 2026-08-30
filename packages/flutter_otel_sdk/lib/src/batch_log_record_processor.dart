import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_otel_api/flutter_otel_api.dart';

/// A [LogRecordProcessor] that buffers records and exports them in batches,
/// either when [maxExportBatchSize] is reached or every [scheduledDelay] on
/// a periodic timer — whichever comes first. Buffered records beyond
/// [maxQueueSize] are dropped (oldest first) to bound memory use.
///
/// Export failures are swallowed and reported via [debugPrint]; they never
/// propagate into application code.
class BatchLogRecordProcessor implements LogRecordProcessor {
  BatchLogRecordProcessor(
    this.exporter,
    this.resource, {
    this.maxQueueSize = 2048,
    this.maxExportBatchSize = 512,
    this.scheduledDelay = const Duration(seconds: 5),
  }) {
    _timer = Timer.periodic(scheduledDelay, (_) => unawaited(_flushBatches()));
  }

  final LogRecordExporter exporter;
  final OTelResource resource;
  final int maxQueueSize;
  final int maxExportBatchSize;
  final Duration scheduledDelay;

  final Queue<LogRecord> _queue = Queue<LogRecord>();
  Timer? _timer;
  bool _shutdown = false;
  Future<void>? _flushInProgress;

  /// The number of records currently buffered, awaiting export. Exposed for
  /// tests.
  @visibleForTesting
  int get queueLength => _queue.length;

  @override
  void onEmit(LogRecord record) {
    if (_shutdown) return;
    if (_queue.length >= maxQueueSize) {
      _queue.removeFirst();
    }
    _queue.add(record);
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
      final batch = List<LogRecord>.generate(
        batchSize,
        (_) => _queue.removeFirst(),
      );
      try {
        final result = await exporter.export(batch, resource);
        if (!result.success) {
          debugPrint('flutter_otel: batch log export failed: ${result.error}');
        }
      } catch (e, stackTrace) {
        debugPrint('flutter_otel: batch log export threw: $e\n$stackTrace');
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
