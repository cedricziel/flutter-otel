import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('NoopSpanExporter', () {
    test('export always succeeds without doing any work', () async {
      const exporter = NoopSpanExporter();
      final resource = OTelResource(serviceName: 'test');
      final span = SpanData(
        name: 'op',
        spanContext: const SpanContext(
          traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          spanId: 'bbbbbbbbbbbbbbbb',
        ),
        startTime: DateTime.now(),
        endTime: DateTime.now(),
      );

      final result = await exporter.export([span], resource);

      expect(result.success, isTrue);
    });

    test('shutdown completes without error', () async {
      const exporter = NoopSpanExporter();
      await expectLater(exporter.shutdown(), completes);
    });
  });
}
