import 'instruments.dart';

/// Creates instruments for one instrumentation scope.
///
/// Asking for an instrument whose [name] was already created on this meter
/// returns the existing one.
abstract class Meter {
  /// The instrumentation scope name this meter was obtained for.
  String get name;

  /// Creates a [Counter].
  Counter createCounter(String name, {String? unit, String? description});

  /// Creates an [UpDownCounter].
  UpDownCounter createUpDownCounter(
    String name, {
    String? unit,
    String? description,
  });

  /// Creates a [Histogram]. [explicitBucketBoundaries] are the ascending
  /// upper bounds of its buckets; when omitted the SDK's defaults apply.
  Histogram createHistogram(
    String name, {
    String? unit,
    String? description,
    List<double>? explicitBucketBoundaries,
  });

  /// Creates a [Gauge].
  Gauge createGauge(String name, {String? unit, String? description});

  /// Creates an [ObservableGauge] whose [callback] reports its measurements
  /// on every collection.
  ObservableGauge createObservableGauge(
    String name,
    ObservableCallback callback, {
    String? unit,
    String? description,
  });
}

/// No-op [Meter] used when metrics have no backing SDK. Every instrument it
/// returns discards its measurements.
class NoopMeter implements Meter {
  const NoopMeter(this.name);

  @override
  final String name;

  @override
  Counter createCounter(String name, {String? unit, String? description}) =>
      const NoopInstrument();

  @override
  UpDownCounter createUpDownCounter(
    String name, {
    String? unit,
    String? description,
  }) =>
      const NoopInstrument();

  @override
  Histogram createHistogram(
    String name, {
    String? unit,
    String? description,
    List<double>? explicitBucketBoundaries,
  }) =>
      const NoopInstrument();

  @override
  Gauge createGauge(String name, {String? unit, String? description}) =>
      const NoopInstrument();

  @override
  ObservableGauge createObservableGauge(
    String name,
    ObservableCallback callback, {
    String? unit,
    String? description,
  }) =>
      const NoopInstrument();
}
