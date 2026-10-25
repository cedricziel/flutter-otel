import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('NoopMeter', () {
    const meter = NoopMeter('scope');

    test('exposes its scope name', () {
      expect(meter.name, 'scope');
    });

    test('hands out instruments that accept measurements silently', () {
      meter.createCounter('c', unit: '1', description: 'd').add(1);
      meter.createUpDownCounter('u').add(-1, attributes: {'k': 'v'});
      meter.createHistogram('h', explicitBucketBoundaries: [1, 2]).record(1.5);
      meter.createGauge('g').record(3);
      final observable = meter.createObservableGauge(
        'o',
        (result) => result.observe(1),
      );

      expect(observable.close, returnsNormally);
    });

    test('never invokes an observable callback', () {
      var calls = 0;
      meter.createObservableGauge('o', (_) => calls++);

      expect(calls, 0);
    });
  });

  group('NoopMeterProvider', () {
    test('returns a meter for the requested scope', () {
      const provider = NoopMeterProvider();

      expect(provider.getMeter(name: 'x').name, 'x');
    });

    test('flushes and shuts down instantly', () async {
      const provider = NoopMeterProvider();

      await expectLater(provider.forceFlush(), completes);
      await expectLater(provider.shutdown(), completes);
    });
  });
}
