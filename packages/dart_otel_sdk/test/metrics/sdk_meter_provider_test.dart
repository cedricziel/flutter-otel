import 'package:dart_otel_sdk/dart_otel_sdk.dart';
import 'package:test/test.dart';

import '../support/fake_metric_reader.dart';

void main() {
  late FakeMetricReader reader;
  late DateTime now;

  SdkMeterProvider newProvider({
    Redactor? redactor,
    int maxCardinality = 2000,
  }) =>
      SdkMeterProvider(
        reader: reader,
        redactor: redactor,
        maxCardinality: maxCardinality,
        clock: () => now,
      );

  setUp(() {
    reader = FakeMetricReader();
    now = DateTime.utc(2026, 1, 1);
  });

  group('Counter', () {
    test('sums integer values into an integer, monotonic sum', () {
      final provider = newProvider();
      final counter = provider.getMeter().createCounter('requests');

      counter.add(2);
      counter.add(3);

      final metric = reader.collect().single as SumMetricData;
      expect(metric.name, 'requests');
      expect(metric.isMonotonic, isTrue);
      expect(metric.points.single.value, 5);
      expect(metric.points.single.value, isA<int>());
    });

    test('promotes the sum to a double once a double is added', () {
      final counter = newProvider().getMeter().createCounter('bytes');

      counter.add(1);
      counter.add(0.5);

      final metric = reader.collect().single as SumMetricData;
      expect(metric.points.single.value, 1.5);
    });

    test('ignores negative and NaN values', () {
      final counter = newProvider().getMeter().createCounter('requests');

      counter.add(2);
      counter.add(-1);
      counter.add(double.nan);

      final metric = reader.collect().single as SumMetricData;
      expect(metric.points.single.value, 2);
    });

    test('keeps one point per attribute set regardless of key order', () {
      final counter = newProvider().getMeter().createCounter('requests');

      counter.add(1, attributes: {'a': 1, 'b': 'x'});
      counter.add(1, attributes: {'b': 'x', 'a': 1});
      counter.add(1, attributes: {'a': '1', 'b': 'x'});

      final metric = reader.collect().single as SumMetricData;
      expect(metric.points, hasLength(2));
      expect(
        metric.points.map((p) => p.value),
        unorderedEquals([2, 1]),
      );
    });

    test('is cumulative across collections', () {
      final counter = newProvider().getMeter().createCounter('requests');

      counter.add(1);
      reader.collect();
      counter.add(1);

      final metric = reader.collect().single as SumMetricData;
      expect(metric.points.single.value, 2);
    });

    test('stamps the provider start time and the collection time', () {
      final counter = newProvider().getMeter().createCounter('requests');
      counter.add(1);
      now = DateTime.utc(2026, 1, 1, 0, 1);

      final point = (reader.collect().single as SumMetricData).points.single;

      expect(point.startTime, DateTime.utc(2026, 1, 1));
      expect(point.time, DateTime.utc(2026, 1, 1, 0, 1));
    });

    test('copies the attributes so later mutation has no effect', () {
      final counter = newProvider().getMeter().createCounter('requests');
      final attributes = <String, Object?>{'a': 1};

      counter.add(1, attributes: attributes);
      attributes['a'] = 2;

      final metric = reader.collect().single as SumMetricData;
      expect(metric.points.single.attributes, {'a': 1});
    });

    test('carries unit, description and scope', () {
      final meter = newProvider().getMeter(name: 'lib', version: '1.2');
      meter.createCounter('requests', unit: '1', description: 'served').add(1);

      final metric = reader.collect().single;

      expect(metric.unit, '1');
      expect(metric.description, 'served');
      expect(metric.scopeName, 'lib');
      expect(metric.scopeVersion, '1.2');
    });
  });

  group('UpDownCounter', () {
    test('sums positive and negative values into a non-monotonic sum', () {
      final counter = newProvider().getMeter().createUpDownCounter('open');

      counter.add(3);
      counter.add(-1);

      final metric = reader.collect().single as SumMetricData;
      expect(metric.isMonotonic, isFalse);
      expect(metric.points.single.value, 2);
    });
  });

  group('Histogram', () {
    test('buckets values with the default boundaries', () {
      final histogram = newProvider().getMeter().createHistogram('latency');

      histogram.record(0);
      histogram.record(5);
      histogram.record(7.5);
      histogram.record(20000);

      final metric = reader.collect().single as HistogramMetricData;
      final point = metric.points.single;
      expect(point.explicitBounds, [
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
      ]);
      expect(point.bucketCounts, hasLength(16));
      expect(point.bucketCounts.sublist(0, 3), [1, 1, 1]);
      expect(point.bucketCounts.last, 1);
      expect(point.count, 4);
      expect(point.sum, 20012.5);
      expect(point.min, 0);
      expect(point.max, 20000);
    });

    test('uses custom boundaries with upper-inclusive buckets', () {
      final histogram = newProvider().getMeter().createHistogram(
        'size',
        explicitBucketBoundaries: [1, 10],
      );

      histogram.record(1);
      histogram.record(1.1);
      histogram.record(10);
      histogram.record(11);

      final point =
          (reader.collect().single as HistogramMetricData).points.single;
      expect(point.explicitBounds, [1, 10]);
      expect(point.bucketCounts, [1, 2, 1]);
    });

    test('falls back to the default boundaries when given invalid ones', () {
      final provider = newProvider();
      provider.getMeter().createHistogram(
        'a',
        explicitBucketBoundaries: [10, 1],
      ).record(1);

      final point =
          (reader.collect().single as HistogramMetricData).points.single;
      expect(point.explicitBounds, hasLength(15));
    });

    test('supports empty boundaries as a single bucket', () {
      newProvider().getMeter().createHistogram(
        'a',
        explicitBucketBoundaries: [],
      ).record(3);

      final point =
          (reader.collect().single as HistogramMetricData).points.single;
      expect(point.bucketCounts, [1]);
    });

    test('ignores negative and NaN values', () {
      final histogram = newProvider().getMeter().createHistogram('latency');

      histogram.record(-1);
      histogram.record(double.nan);
      histogram.record(1);

      final point =
          (reader.collect().single as HistogramMetricData).points.single;
      expect(point.count, 1);
    });
  });

  group('Gauge', () {
    test('reports the last value per attribute set', () {
      final gauge = newProvider().getMeter().createGauge('temperature');

      gauge.record(20);
      gauge.record(21.5);
      gauge.record(5, attributes: {'room': 'b'});

      final metric = reader.collect().single as GaugeMetricData;
      final byRoom = {
        for (final p in metric.points) p.attributes['room']: p.value,
      };
      expect(byRoom, {null: 21.5, 'b': 5});
    });
  });

  group('ObservableGauge', () {
    test('invokes the callback on every collection', () {
      var reading = 1;
      newProvider().getMeter().createObservableGauge(
            'battery',
            (result) => result.observe(reading++, attributes: {'k': 'v'}),
          );

      final first = reader.collect().single as GaugeMetricData;
      final second = reader.collect().single as GaugeMetricData;

      expect(first.points.single.value, 1);
      expect(second.points.single.value, 2);
      expect(second.points.single.attributes, {'k': 'v'});
    });

    test('keeps the last observation per attribute set within a collection',
        () {
      newProvider().getMeter().createObservableGauge('battery', (result) {
        result.observe(1);
        result.observe(2);
      });

      final metric = reader.collect().single as GaugeMetricData;
      expect(metric.points.single.value, 2);
    });

    test('stops reporting after close', () {
      var calls = 0;
      final gauge = newProvider().getMeter().createObservableGauge(
        'battery',
        (result) {
          calls++;
          result.observe(1);
        },
      );

      gauge.close();

      expect(reader.collect(), isEmpty);
      expect(calls, 0);
    });

    test('survives a throwing callback', () {
      final meter = newProvider().getMeter();
      meter.createObservableGauge('bad', (_) => throw StateError('boom'));
      meter.createCounter('good').add(1);

      expect(reader.collect().map((m) => m.name), ['good']);
    });

    test('reports nothing when the callback observes nothing', () {
      newProvider().getMeter().createObservableGauge('quiet', (_) {});

      expect(reader.collect(), isEmpty);
    });
  });

  group('SdkMeterProvider', () {
    test('registers itself with the reader', () {
      final provider = newProvider();

      expect(reader.producer, same(provider));
    });

    test('omits instruments that recorded nothing', () {
      newProvider().getMeter().createCounter('unused');

      expect(reader.collect(), isEmpty);
    });

    test('returns the existing instrument for a repeated name', () {
      final meter = newProvider().getMeter();

      meter.createCounter('requests').add(1);
      meter.createCounter('requests').add(1);

      final metric = reader.collect().single as SumMetricData;
      expect(metric.points.single.value, 2);
    });

    test('keeps same-named instruments of different kinds apart', () {
      final meter = newProvider().getMeter();

      meter.createCounter('x').add(1);
      meter.createUpDownCounter('x').add(1);

      expect(reader.collect(), hasLength(2));
    });

    test('returns the same meter for the same scope', () {
      final provider = newProvider();

      expect(provider.getMeter(name: 'a'), same(provider.getMeter(name: 'a')));
      expect(
        provider.getMeter(name: 'a'),
        isNot(same(provider.getMeter(name: 'a', version: '1'))),
      );
    });

    test('collects instruments of every meter', () {
      final provider = newProvider();
      provider.getMeter(name: 'a').createCounter('x').add(1);
      provider.getMeter(name: 'b').createCounter('x').add(1);

      expect(reader.collect().map((m) => m.scopeName), ['a', 'b']);
    });

    test('delegates flush and shutdown to the reader', () async {
      final provider = newProvider();

      await provider.forceFlush();
      await provider.shutdown();

      expect(reader.flushCount, 1);
      expect(reader.shutdownCount, 1);
    });

    test('hands out no-op meters after shutdown', () async {
      final provider = newProvider();
      await provider.shutdown();

      provider.getMeter().createCounter('late').add(1);

      expect(reader.collect(), isEmpty);
    });
  });

  group('cardinality limit', () {
    test('folds attribute sets beyond the limit into an overflow point', () {
      final counter = newProvider(maxCardinality: 3).getMeter().createCounter(
            'requests',
          );

      for (var i = 0; i < 5; i++) {
        counter.add(1, attributes: {'id': i});
      }
      counter.add(1, attributes: {'id': 0});

      final metric = reader.collect().single as SumMetricData;
      expect(metric.points, hasLength(3));
      final byAttributes = {
        for (final p in metric.points) p.attributes.toString(): p.value,
      };
      expect(byAttributes, {
        '{id: 0}': 2,
        '{id: 1}': 1,
        '{otel.metric.overflow: true}': 3,
      });
    });

    test('applies to observable gauges as well', () {
      newProvider(maxCardinality: 2).getMeter().createObservableGauge(
        'g',
        (result) {
          for (var i = 0; i < 4; i++) {
            result.observe(i, attributes: {'id': i});
          }
        },
      );

      final metric = reader.collect().single as GaugeMetricData;
      expect(metric.points, hasLength(2));
    });

    test('rejects a non-positive limit', () {
      expect(
        () => newProvider(maxCardinality: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('redaction', () {
    test('redacts attribute values before they key a data point', () {
      final counter = newProvider(redactor: PatternRedactor())
          .getMeter()
          .createCounter('requests');

      counter.add(1, attributes: {'url': 'https://user:pw@host/', 'n': 1});
      counter.add(1, attributes: {'url': 'https://other:pw2@host/', 'n': 1});
      counter.add(1, attributes: {'api_key': 'abc'});

      final metric = reader.collect().single as SumMetricData;
      final byAttributes = {
        for (final p in metric.points) p.attributes.toString(): p.value,
      };
      expect(byAttributes, {
        '{url: https://[REDACTED]@host/, n: 1}': 2,
        '{api_key: [REDACTED]}': 1,
      });
    });
  });
}
