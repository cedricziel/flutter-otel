import 'dart:async';
import 'dart:io';

import 'package:dart_otel_api/dart_otel_api.dart';

import 'metric_reader.dart';

/// A [MetricReader] that collects and exports on a fixed [interval].
///
/// Metrics are cumulative, so a skipped or failed export loses nothing: the
/// next one carries the full totals. Failures are reported to [stderr] and
/// never propagate into application code.
class PeriodicExportingMetricReader implements MetricReader {
  PeriodicExportingMetricReader(
    this.exporter,
    this.resource, {
    this.interval = const Duration(seconds: 60),
  }) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(
        interval,
        'interval',
        'Must be greater than Duration.zero.',
      );
    }
    _timer = Timer.periodic(interval, (_) {
      if (_inFlight == null) unawaited(_export());
    });
  }

  final MetricExporter exporter;
  final OTelResource resource;
  final Duration interval;

  MetricProducer? _producer;
  Timer? _timer;
  bool _shutdown = false;
  Future<void>? _inFlight;

  @override
  void register(MetricProducer producer) => _producer = producer;

  @override
  Future<void> forceFlush() => _export();

  // Exports run one after another so a forced flush never reports older
  // totals than an export that was already under way.
  Future<void> _export() {
    final next = (_inFlight ?? Future<void>.value()).then(
      (_) => _collectAndExport(),
    );
    _inFlight = next;
    return next.whenComplete(() {
      if (identical(_inFlight, next)) _inFlight = null;
    });
  }

  Future<void> _collectAndExport() async {
    final producer = _producer;
    if (producer == null || _shutdown) return;
    try {
      final metrics = producer.collect();
      if (metrics.isEmpty) return;
      final result = await exporter.export(metrics, resource);
      if (!result.success) {
        stderr.writeln('flutter_otel: metric export failed: ${result.error}');
      }
    } catch (e, stackTrace) {
      stderr.writeln('flutter_otel: metric export threw: $e\n$stackTrace');
    }
  }

  @override
  Future<void> shutdown() async {
    if (_shutdown) return;
    _timer?.cancel();
    _timer = null;
    await _export();
    _shutdown = true;
    await exporter.shutdown();
  }
}
