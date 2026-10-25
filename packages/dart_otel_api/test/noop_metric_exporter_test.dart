import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('NoopMetricExporter', () {
    const exporter = NoopMetricExporter();
    final resource = OTelResource(serviceName: 'test');

    test('reports success for an empty batch', () async {
      final result = await exporter.export([], resource);

      expect(result.success, isTrue);
    });

    test('reports success for a non-empty batch', () async {
      final metric = SumMetricData(
        name: 'requests',
        description: null,
        unit: null,
        scopeName: 'scope',
        scopeVersion: null,
        isMonotonic: true,
        points: [
          NumberDataPoint(
            attributes: const {},
            startTime: DateTime.utc(2026),
            time: DateTime.utc(2026),
            value: 1,
          ),
        ],
      );

      final result = await exporter.export([metric], resource);

      expect(result.success, isTrue);
    });

    test('shutdown completes without error', () async {
      await expectLater(exporter.shutdown(), completes);
    });
  });
}
