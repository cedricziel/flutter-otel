import 'package:dart_otel_api/dart_otel_api.dart';

import '../redactor.dart';
import 'sdk_instruments.dart';

/// Creates the instruments of one instrumentation scope and snapshots them.
class SdkMeter implements Meter {
  SdkMeter({
    required this.name,
    required this.version,
    required this.maxCardinality,
    required this.redactor,
  });

  @override
  final String name;
  final String? version;
  final int maxCardinality;
  final Redactor? redactor;

  // Keyed by kind as well as name so a clash across kinds yields two
  // streams instead of failing in the caller's code.
  final Map<(String, String), SdkInstrument> _instruments = {};

  /// Snapshots every instrument that has data.
  Iterable<MetricData> collect(DateTime start, DateTime now) sync* {
    for (final instrument in _instruments.values) {
      final data = instrument.collect(start, now);
      if (data != null) yield data;
    }
  }

  T _instrument<T extends SdkInstrument>(
    String kind,
    String name,
    T Function() create,
  ) =>
      _instruments.putIfAbsent((kind, name), create) as T;

  @override
  Counter createCounter(String name, {String? unit, String? description}) =>
      _sum(name, unit, description, isMonotonic: true);

  @override
  UpDownCounter createUpDownCounter(
    String name, {
    String? unit,
    String? description,
  }) =>
      _sum(name, unit, description, isMonotonic: false);

  SdkSum _sum(
    String name,
    String? unit,
    String? description, {
    required bool isMonotonic,
  }) =>
      _instrument(
        isMonotonic ? 'counter' : 'upDownCounter',
        name,
        () => SdkSum(
          name: name,
          unit: unit,
          description: description,
          scopeName: this.name,
          scopeVersion: version,
          maxCardinality: maxCardinality,
          redactor: redactor,
          isMonotonic: isMonotonic,
        ),
      );

  @override
  Histogram createHistogram(
    String name, {
    String? unit,
    String? description,
    List<double>? explicitBucketBoundaries,
  }) =>
      _instrument<SdkHistogram>(
        'histogram',
        name,
        () => SdkHistogram(
          name: name,
          unit: unit,
          description: description,
          scopeName: this.name,
          scopeVersion: version,
          maxCardinality: maxCardinality,
          redactor: redactor,
          boundaries: explicitBucketBoundaries,
        ),
      );

  @override
  Gauge createGauge(String name, {String? unit, String? description}) =>
      _instrument<SdkGauge>(
        'gauge',
        name,
        () => SdkGauge(
          name: name,
          unit: unit,
          description: description,
          scopeName: this.name,
          scopeVersion: version,
          maxCardinality: maxCardinality,
          redactor: redactor,
        ),
      );

  @override
  ObservableGauge createObservableGauge(
    String name,
    ObservableCallback callback, {
    String? unit,
    String? description,
  }) =>
      _instrument<SdkObservableGauge>(
        'observableGauge',
        name,
        () => SdkObservableGauge(
          name: name,
          unit: unit,
          description: description,
          scopeName: this.name,
          scopeVersion: version,
          maxCardinality: maxCardinality,
          redactor: redactor,
          callback: callback,
        ),
      );
}
