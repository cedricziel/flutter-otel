import 'package:dart_otel_sdk/dart_otel_sdk.dart';
import 'package:test/test.dart';

import 'support/fake_log_record_exporter.dart';

void main() {
  late FakeLogRecordExporter exporter;
  late OTelResource resource;
  late SimpleLogRecordProcessor processor;

  setUp(() {
    exporter = FakeLogRecordExporter();
    resource = OTelResource(serviceName: 'test');
    processor = SimpleLogRecordProcessor(exporter, resource);
  });

  group('SimpleLogRecordProcessor', () {
    test('forwards each emitted record to the exporter immediately', () async {
      processor.onEmit(LogRecord(body: 'one'));
      await processor.forceFlush();

      expect(exporter.exportedBatches, hasLength(1));
      expect(exporter.exportedBatches.single, hasLength(1));
      expect(exporter.exportedBatches.single.single.body, 'one');
      expect(exporter.resources.single, resource);
    });

    test('exports each record as its own batch, not merged together', () async {
      processor.onEmit(LogRecord(body: 'one'));
      processor.onEmit(LogRecord(body: 'two'));
      await processor.forceFlush();

      expect(exporter.exportedBatches, hasLength(2));
      expect(exporter.allRecords.map((r) => r.body), ['one', 'two']);
    });

    test('forceFlush waits for in-flight exports to complete', () async {
      exporter.gate = null;
      processor.onEmit(LogRecord(body: 'one'));

      await processor.forceFlush();

      expect(exporter.exportedBatches, hasLength(1));
    });

    test('swallows a failed export instead of throwing', () async {
      exporter.nextResult = const ExportResult.failure('boom');
      processor.onEmit(LogRecord(body: 'one'));

      await expectLater(processor.forceFlush(), completes);
    });

    test('shutdown flushes pending records and shuts down the exporter',
        () async {
      processor.onEmit(LogRecord(body: 'one'));
      await processor.shutdown();

      expect(exporter.exportedBatches, hasLength(1));
      expect(exporter.shutdownCallCount, 1);
    });

    test('onEmit after shutdown is a no-op and never touches the exporter',
        () async {
      processor.onEmit(LogRecord(body: 'one'));
      await processor.shutdown();

      expect(exporter.exportedBatches, hasLength(1));

      processor.onEmit(LogRecord(body: 'two'));
      await Future<void>.delayed(Duration.zero);

      // Still just the one record exported before shutdown; the post-
      // shutdown emit was dropped rather than exported through a released
      // exporter.
      expect(exporter.exportedBatches, hasLength(1));
      expect(exporter.allRecords.map((r) => r.body), ['one']);
    });
  });
}
