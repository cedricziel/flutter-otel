import 'dart:io';

import 'package:dart_otel_api/dart_otel_api.dart';

import '../redactor.dart';
import 'attributed_points.dart';

/// The default explicit bucket boundaries of the specification.
const List<double> defaultHistogramBoundaries = [
  0,
  5,
  10,
  25,
  50,
  75,
  100,
  250,
  500,
  750,
  1000,
  2500,
  5000,
  7500,
  10000,
];

class _Cell {
  num value = 0;
}

/// An instrument that can snapshot its cumulative state.
abstract class SdkInstrument {
  SdkInstrument({
    required this.name,
    required this.unit,
    required this.description,
    required this.scopeName,
    required this.scopeVersion,
    required this.maxCardinality,
    required Redactor? redactor,
  }) : _redactor = redactor;

  final String name;
  final String? unit;
  final String? description;
  final String scopeName;
  final String? scopeVersion;
  final int maxCardinality;
  final Redactor? _redactor;

  /// Snapshots the data points, or returns `null` when nothing was recorded.
  /// [start] is when aggregation began, [now] the collection time.
  MetricData? collect(DateTime start, DateTime now);

  /// Redacts [attributes] before they are used as a data point key.
  MetricAttributes sanitize(MetricAttributes attributes) =>
      _redactor == null ? attributes : redactAttributes(attributes, _redactor);
}

List<NumberDataPoint> _numberPoints(
  AttributedPoints<_Cell> points,
  DateTime start,
  DateTime now,
) =>
    [
      for (final (attributes, cell) in points.entries)
        NumberDataPoint(
          attributes: attributes,
          startTime: start,
          time: now,
          value: cell.value,
        ),
    ];

/// Rejects NaN and infinite measurements, which would poison a sum.
bool _isUsable(num value) => value.isFinite;

/// The aggregation behind both [Counter] and [UpDownCounter].
class SdkSum extends SdkInstrument implements Counter, UpDownCounter {
  SdkSum({
    required super.name,
    required super.unit,
    required super.description,
    required super.scopeName,
    required super.scopeVersion,
    required super.maxCardinality,
    required super.redactor,
    required this.isMonotonic,
  }) : _points = AttributedPoints(maxCardinality);

  final bool isMonotonic;
  final AttributedPoints<_Cell> _points;

  @override
  void add(num value, {MetricAttributes attributes = const {}}) {
    if (!_isUsable(value) || (isMonotonic && value < 0)) return;
    _points.of(sanitize(attributes), _Cell.new).value += value;
  }

  @override
  MetricData? collect(DateTime start, DateTime now) {
    if (_points.isEmpty) return null;
    return SumMetricData(
      name: name,
      description: description,
      unit: unit,
      scopeName: scopeName,
      scopeVersion: scopeVersion,
      isMonotonic: isMonotonic,
      points: _numberPoints(_points, start, now),
    );
  }
}

class _Distribution {
  _Distribution(int buckets) : bucketCounts = List.filled(buckets, 0);

  final List<int> bucketCounts;
  int count = 0;
  double sum = 0;
  double min = double.infinity;
  double max = double.negativeInfinity;
}

/// Explicit-bucket histogram aggregation.
class SdkHistogram extends SdkInstrument implements Histogram {
  SdkHistogram({
    required super.name,
    required super.unit,
    required super.description,
    required super.scopeName,
    required super.scopeVersion,
    required super.maxCardinality,
    required super.redactor,
    List<double>? boundaries,
  })  : boundaries = _validBoundaries(boundaries)
            ? List.unmodifiable(boundaries!)
            : defaultHistogramBoundaries,
        _points = AttributedPoints(maxCardinality);

  /// Ascending upper bounds; bucket `i` counts values `<= boundaries[i]`
  /// and the last bucket everything above the final bound.
  final List<double> boundaries;
  final AttributedPoints<_Distribution> _points;

  static bool _validBoundaries(List<double>? boundaries) {
    if (boundaries == null) return false;
    for (var i = 0; i < boundaries.length; i++) {
      if (boundaries[i].isNaN ||
          (i > 0 && boundaries[i] <= boundaries[i - 1])) {
        return false;
      }
    }
    return true;
  }

  @override
  void record(num value, {MetricAttributes attributes = const {}}) {
    if (!_isUsable(value) || value < 0) return;
    final v = value.toDouble();
    final distribution = _points.of(
      sanitize(attributes),
      () => _Distribution(boundaries.length + 1),
    );
    var bucket = boundaries.indexWhere((bound) => v <= bound);
    if (bucket < 0) bucket = boundaries.length;
    distribution.bucketCounts[bucket]++;
    distribution.count++;
    distribution.sum += v;
    if (v < distribution.min) distribution.min = v;
    if (v > distribution.max) distribution.max = v;
  }

  @override
  MetricData? collect(DateTime start, DateTime now) {
    if (_points.isEmpty) return null;
    return HistogramMetricData(
      name: name,
      description: description,
      unit: unit,
      scopeName: scopeName,
      scopeVersion: scopeVersion,
      points: [
        for (final (attributes, d) in _points.entries)
          HistogramDataPoint(
            attributes: attributes,
            startTime: start,
            time: now,
            count: d.count,
            sum: d.sum,
            min: d.min,
            max: d.max,
            bucketCounts: List.of(d.bucketCounts),
            explicitBounds: boundaries,
          ),
      ],
    );
  }
}

/// Last-value aggregation for the synchronous [Gauge].
class SdkGauge extends SdkInstrument implements Gauge {
  SdkGauge({
    required super.name,
    required super.unit,
    required super.description,
    required super.scopeName,
    required super.scopeVersion,
    required super.maxCardinality,
    required super.redactor,
  }) : _points = AttributedPoints(maxCardinality);

  final AttributedPoints<_Cell> _points;

  @override
  void record(num value, {MetricAttributes attributes = const {}}) {
    if (!_isUsable(value)) return;
    _points.of(sanitize(attributes), _Cell.new).value = value;
  }

  @override
  MetricData? collect(DateTime start, DateTime now) {
    if (_points.isEmpty) return null;
    return GaugeMetricData(
      name: name,
      description: description,
      unit: unit,
      scopeName: scopeName,
      scopeVersion: scopeVersion,
      points: _numberPoints(_points, start, now),
    );
  }
}

/// A gauge whose callback reports fresh measurements on every collection.
class SdkObservableGauge extends SdkInstrument
    implements ObservableGauge, ObservableResult {
  SdkObservableGauge({
    required super.name,
    required super.unit,
    required super.description,
    required super.scopeName,
    required super.scopeVersion,
    required super.maxCardinality,
    required super.redactor,
    required ObservableCallback callback,
  }) : _callback = callback;

  final ObservableCallback _callback;
  bool _closed = false;
  AttributedPoints<_Cell>? _observations;

  @override
  void observe(num value, {MetricAttributes attributes = const {}}) {
    if (!_isUsable(value)) return;
    _observations?.of(sanitize(attributes), _Cell.new).value = value;
  }

  @override
  void close() => _closed = true;

  @override
  MetricData? collect(DateTime start, DateTime now) {
    if (_closed) return null;
    final observations = _observations = AttributedPoints(maxCardinality);
    try {
      _callback(this);
    } catch (e, stackTrace) {
      stderr.writeln(
        'flutter_otel: observable gauge "$name" callback threw: $e\n'
        '$stackTrace',
      );
    } finally {
      _observations = null;
    }
    if (observations.isEmpty) return null;
    return GaugeMetricData(
      name: name,
      description: description,
      unit: unit,
      scopeName: scopeName,
      scopeVersion: scopeVersion,
      points: _numberPoints(observations, start, now),
    );
  }
}
