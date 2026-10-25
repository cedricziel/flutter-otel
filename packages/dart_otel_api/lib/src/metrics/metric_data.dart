/// One aggregated measurement series: the values recorded for a single
/// attribute set over `[startTime, time]`.
sealed class MetricDataPoint {
  const MetricDataPoint({
    required this.attributes,
    required this.startTime,
    required this.time,
  });

  final Map<String, Object?> attributes;

  /// When the cumulative aggregation began.
  final DateTime startTime;

  /// When the aggregation was collected.
  final DateTime time;
}

/// A single `int` or `double` value, used by sums and gauges.
final class NumberDataPoint extends MetricDataPoint {
  const NumberDataPoint({
    required super.attributes,
    required super.startTime,
    required super.time,
    required this.value,
  });

  final num value;
}

/// A bucketed distribution. [bucketCounts] has one more entry than
/// [explicitBounds]: the last bucket counts values above the final bound.
final class HistogramDataPoint extends MetricDataPoint {
  const HistogramDataPoint({
    required super.attributes,
    required super.startTime,
    required super.time,
    required this.count,
    required this.sum,
    this.min,
    this.max,
    required this.bucketCounts,
    required this.explicitBounds,
  });

  final int count;
  final double sum;
  final double? min;
  final double? max;
  final List<int> bucketCounts;
  final List<double> explicitBounds;
}

/// A named metric and its data points, always with cumulative temporality.
sealed class MetricData {
  const MetricData({
    required this.name,
    required this.description,
    required this.unit,
    required this.scopeName,
    required this.scopeVersion,
  });

  final String name;
  final String? description;
  final String? unit;
  final String scopeName;
  final String? scopeVersion;

  List<MetricDataPoint> get points;
}

/// Counter or up-down counter data. [isMonotonic] is `true` for counters.
final class SumMetricData extends MetricData {
  const SumMetricData({
    required super.name,
    required super.description,
    required super.unit,
    required super.scopeName,
    required super.scopeVersion,
    required this.isMonotonic,
    required this.points,
  });

  final bool isMonotonic;

  @override
  final List<NumberDataPoint> points;
}

/// Gauge data: the latest value per attribute set.
final class GaugeMetricData extends MetricData {
  const GaugeMetricData({
    required super.name,
    required super.description,
    required super.unit,
    required super.scopeName,
    required super.scopeVersion,
    required this.points,
  });

  @override
  final List<NumberDataPoint> points;
}

/// Histogram data.
final class HistogramMetricData extends MetricData {
  const HistogramMetricData({
    required super.name,
    required super.description,
    required super.unit,
    required super.scopeName,
    required super.scopeVersion,
    required this.points,
  });

  @override
  final List<HistogramDataPoint> points;
}
