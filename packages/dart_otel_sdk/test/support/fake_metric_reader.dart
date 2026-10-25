import 'package:dart_otel_sdk/dart_otel_sdk.dart';

/// A [MetricReader] that collects only when a test asks it to.
class FakeMetricReader implements MetricReader {
  MetricProducer? producer;
  int flushCount = 0;
  int shutdownCount = 0;

  @override
  void register(MetricProducer producer) => this.producer = producer;

  List<MetricData> collect() => producer!.collect();

  @override
  Future<void> forceFlush() async => flushCount++;

  @override
  Future<void> shutdown() async => shutdownCount++;
}
