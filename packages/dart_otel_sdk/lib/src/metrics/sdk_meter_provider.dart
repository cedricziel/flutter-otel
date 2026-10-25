import 'package:dart_otel_api/dart_otel_api.dart';

import '../redactor.dart';
import 'metric_reader.dart';
import 'sdk_meter.dart';

/// Concrete [MeterProvider] that aggregates instruments with cumulative
/// temporality and serves them to a [MetricReader].
///
/// Each instrument keeps at most [maxCardinality] distinct attribute sets;
/// further sets are folded into one `otel.metric.overflow` data point. When a
/// [redactor] is set, attribute values are redacted before they are
/// aggregated.
class SdkMeterProvider implements MeterProvider, MetricProducer {
  SdkMeterProvider({
    required this.reader,
    this.redactor,
    this.maxCardinality = 2000,
    DateTime Function() clock = DateTime.now,
  })  : _clock = clock,
        _startTime = clock().toUtc() {
    if (maxCardinality <= 0) {
      throw ArgumentError.value(
        maxCardinality,
        'maxCardinality',
        'Must be greater than 0.',
      );
    }
    reader.register(this);
  }

  final MetricReader reader;
  final Redactor? redactor;
  final int maxCardinality;

  final DateTime Function() _clock;
  final DateTime _startTime;
  final Map<(String, String?), SdkMeter> _meters = {};
  bool _shutdown = false;

  @override
  Meter getMeter({String name = 'flutter_otel', String? version}) {
    if (_shutdown) return NoopMeter(name);
    return _meters.putIfAbsent(
      (name, version),
      () => SdkMeter(
        name: name,
        version: version,
        maxCardinality: maxCardinality,
        redactor: redactor,
      ),
    );
  }

  @override
  List<MetricData> collect() {
    final now = _clock().toUtc();
    return [
      for (final meter in _meters.values) ...meter.collect(_startTime, now),
    ];
  }

  @override
  Future<void> forceFlush() => reader.forceFlush();

  @override
  Future<void> shutdown() async {
    _shutdown = true;
    await reader.shutdown();
  }
}
