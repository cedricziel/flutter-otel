/// Attributes attached to a single measurement; each distinct set produces
/// its own data point.
typedef MetricAttributes = Map<String, Object?>;

/// Records monotonically increasing values, such as requests served.
///
/// Values are `num`: an instrument fed only `int`s reports integer data
/// points, one fed any `double` reports doubles.
abstract class Counter {
  /// Adds [value] to the sum. Negative values are ignored, since a counter
  /// can only go up.
  void add(num value, {MetricAttributes attributes = const {}});
}

/// Records values that can go up and down, such as open connections.
abstract class UpDownCounter {
  /// Adds [value], which may be negative, to the sum.
  void add(num value, {MetricAttributes attributes = const {}});
}

/// Records a distribution of values, such as request durations.
abstract class Histogram {
  /// Records one [value] into the distribution. Negative values are ignored.
  void record(num value, {MetricAttributes attributes = const {}});
}

/// Records the current value of something measured inline, such as the
/// temperature when a sensor reading arrives. Only the latest value per
/// attribute set is reported.
abstract class Gauge {
  /// Sets the current [value].
  void record(num value, {MetricAttributes attributes = const {}});
}

/// Passed to an observable instrument's callback to report measurements.
abstract class ObservableResult {
  /// Reports one measurement for the current collection.
  void observe(num value, {MetricAttributes attributes = const {}});
}

/// Called once per collection to report the current state of an
/// [ObservableGauge]. Must not block.
typedef ObservableCallback = void Function(ObservableResult result);

/// Handle for an asynchronous gauge registered through
/// `Meter.createObservableGauge`; its callback runs on every collection.
abstract class ObservableGauge {
  /// Stops invoking the callback.
  void close();
}

/// Instrument that discards everything it is given.
class NoopInstrument
    implements Counter, UpDownCounter, Histogram, Gauge, ObservableGauge {
  const NoopInstrument();

  @override
  void add(num value, {MetricAttributes attributes = const {}}) {}

  @override
  void record(num value, {MetricAttributes attributes = const {}}) {}

  @override
  void close() {}
}
