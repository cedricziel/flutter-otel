import 'dart:async';

import 'package:dart_otel_sdk/dart_otel_sdk.dart';
import 'package:test/test.dart';

import '../support/fake_metric_exporter.dart';

void main() {
  late FakeMetricExporter exporter;
  late OTelResource resource;

  setUp(() {
    exporter = FakeMetricExporter();
    resource = OTelResource(serviceName: 'test');
  });

  PeriodicExportingMetricReader newReader({
    Duration interval = const Duration(minutes: 10),
  }) =>
      PeriodicExportingMetricReader(exporter, resource, interval: interval);

  SdkMeterProvider newProvider(MetricReader reader) =>
      SdkMeterProvider(reader: reader);

  group('PeriodicExportingMetricReader', () {
    test('defaults to a 60 second interval', () async {
      final defaults = PeriodicExportingMetricReader(exporter, resource);
      addTearDown(defaults.shutdown);

      expect(defaults.interval, const Duration(seconds: 60));
    });

    test('rejects a non-positive interval', () {
      expect(
        () => newReader(interval: Duration.zero),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('exports collected metrics on its timer', () async {
      final reader = newReader(interval: const Duration(milliseconds: 10));
      final provider = newProvider(reader);
      addTearDown(provider.shutdown);
      provider.getMeter().createCounter('requests').add(1);

      await exporter.nextExport;

      expect(exporter.exportedBatches.first.single.name, 'requests');
      expect(exporter.resources.first, same(resource));
    });

    test('forceFlush exports immediately and exports cumulative values',
        () async {
      final reader = newReader();
      final provider = newProvider(reader);
      addTearDown(provider.shutdown);
      final counter = provider.getMeter().createCounter('requests');

      counter.add(1);
      await provider.forceFlush();
      counter.add(1);
      await provider.forceFlush();

      final values = [
        for (final batch in exporter.exportedBatches)
          (batch.single as SumMetricData).points.single.value,
      ];
      expect(values, [1, 2]);
    });

    test('does not call the exporter when there is nothing to export',
        () async {
      final reader = newReader();
      final provider = newProvider(reader);
      addTearDown(provider.shutdown);

      await provider.forceFlush();

      expect(exporter.exportedBatches, isEmpty);
    });

    test('forceFlush before registration is a no-op', () async {
      final reader = newReader();
      addTearDown(reader.shutdown);

      await expectLater(reader.forceFlush(), completes);

      expect(exporter.exportedBatches, isEmpty);
    });

    test('shutdown performs a final export and shuts the exporter down',
        () async {
      final reader = newReader();
      final provider = newProvider(reader);
      provider.getMeter().createCounter('requests').add(1);

      await provider.shutdown();

      expect(exporter.exportedBatches, hasLength(1));
      expect(exporter.shutdownCallCount, 1);
    });

    test('concurrent shutdowns share one final export', () async {
      final reader = newReader();
      final provider = newProvider(reader);
      provider.getMeter().createCounter('requests').add(1);

      await Future.wait([reader.shutdown(), reader.shutdown()]);

      expect(exporter.exportedBatches, hasLength(1));
      expect(exporter.shutdownCallCount, 1);
    });

    test('stops exporting after shutdown', () async {
      final reader = newReader(interval: const Duration(milliseconds: 5));
      final provider = newProvider(reader);
      final counter = provider.getMeter().createCounter('requests');
      counter.add(1);
      await provider.shutdown();
      final exported = exporter.exportedBatches.length;

      counter.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await reader.forceFlush();

      expect(exporter.exportedBatches, hasLength(exported));
    });

    test('swallows failed exports', () async {
      exporter.nextResult = const ExportResult.failure('nope');
      final reader = newReader();
      final provider = newProvider(reader);
      addTearDown(provider.shutdown);
      provider.getMeter().createCounter('requests').add(1);

      await expectLater(provider.forceFlush(), completes);
    });

    test('swallows exporters that throw', () async {
      final reader = PeriodicExportingMetricReader(
        _ThrowingExporter(),
        resource,
        interval: const Duration(minutes: 10),
      );
      final provider = newProvider(reader);
      addTearDown(provider.shutdown);
      provider.getMeter().createCounter('requests').add(1);

      await expectLater(provider.forceFlush(), completes);
    });

    test('serializes overlapping exports', () async {
      final reader = newReader();
      final provider = newProvider(reader);
      addTearDown(provider.shutdown);
      provider.getMeter().createCounter('requests').add(1);
      exporter.gate = Completer<void>();

      final first = provider.forceFlush();
      final second = provider.forceFlush();
      await Future<void>.delayed(Duration.zero);
      expect(exporter.exportedBatches, isEmpty);
      exporter.gate!.complete();
      await Future.wait([first, second]);

      expect(exporter.exportedBatches, hasLength(2));
    });
  });
}

class _ThrowingExporter implements MetricExporter {
  @override
  Future<ExportResult> export(
    List<MetricData> metrics,
    OTelResource resource,
  ) =>
      throw StateError('boom');

  @override
  Future<void> shutdown() async {}
}
