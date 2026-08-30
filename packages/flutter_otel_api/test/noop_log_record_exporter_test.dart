import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('NoopLogRecordExporter', () {
    test('always reports success without needing any records', () async {
      const exporter = NoopLogRecordExporter();
      final resource = OTelResource(serviceName: 'test');

      final result = await exporter.export([], resource);

      expect(result.success, isTrue);
    });

    test('reports success even for a non-empty batch', () async {
      const exporter = NoopLogRecordExporter();
      final resource = OTelResource(serviceName: 'test');
      final records = [LogRecord(body: 'hello')];

      final result = await exporter.export(records, resource);

      expect(result.success, isTrue);
    });

    test('shutdown completes without error', () async {
      const exporter = NoopLogRecordExporter();
      await expectLater(exporter.shutdown(), completes);
    });
  });
}
