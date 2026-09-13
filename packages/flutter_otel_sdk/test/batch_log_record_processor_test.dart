import 'package:flutter_otel_sdk/flutter_otel_sdk.dart';
import 'package:test/test.dart';

import 'support/fake_log_record_exporter.dart';

void main() {
  late FakeLogRecordExporter exporter;
  late OTelResource resource;

  setUp(() {
    exporter = FakeLogRecordExporter();
    resource = OTelResource(serviceName: 'test');
  });

  group('BatchLogRecordProcessor', () {
    test('buffers records without exporting until a threshold is reached',
        () async {
      final processor = BatchLogRecordProcessor(
        exporter,
        resource,
        maxExportBatchSize: 10,
        scheduledDelay: const Duration(minutes: 10),
      );
      addTearDown(processor.shutdown);

      processor.onEmit(LogRecord(body: 'one'));
      // Give any stray microtasks a chance to run; there should be none.
      await Future<void>.delayed(Duration.zero);

      expect(exporter.exportedBatches, isEmpty);
      expect(processor.queueLength, 1);
    });

    test('automatically flushes once maxExportBatchSize is reached', () async {
      final processor = BatchLogRecordProcessor(
        exporter,
        resource,
        maxExportBatchSize: 2,
        scheduledDelay: const Duration(minutes: 10),
      );
      addTearDown(processor.shutdown);

      final exported = exporter.nextExport;
      processor.onEmit(LogRecord(body: 'one'));
      processor.onEmit(LogRecord(body: 'two'));
      // Await the processor's own automatic export triggered by onEmit
      // reaching maxExportBatchSize — not a forced flush — so a regression
      // that removes the auto-flush-on-threshold logic would actually fail
      // this test (it would otherwise hang and time out).
      await exported;

      expect(exporter.allRecords.map((r) => r.body), ['one', 'two']);
      expect(processor.queueLength, 0);
    });

    test('splits a large forced flush into batches of maxExportBatchSize',
        () async {
      final processor = BatchLogRecordProcessor(
        exporter,
        resource,
        maxExportBatchSize: 2,
        maxQueueSize: 100,
        scheduledDelay: const Duration(minutes: 10),
      );
      addTearDown(processor.shutdown);

      for (var i = 0; i < 5; i++) {
        processor.onEmit(LogRecord(body: 'record-$i'));
      }
      await processor.forceFlush();

      // 5 records at a batch size of 2 -> batches of [2, 2, 1].
      expect(exporter.exportedBatches.map((b) => b.length), [2, 2, 1]);
      expect(exporter.allRecords, hasLength(5));
    });

    test('drops the oldest record once maxQueueSize is exceeded', () async {
      final processor = BatchLogRecordProcessor(
        exporter,
        resource,
        maxQueueSize: 2,
        maxExportBatchSize: 100,
        scheduledDelay: const Duration(minutes: 10),
      );
      addTearDown(processor.shutdown);

      processor.onEmit(LogRecord(body: 'one'));
      processor.onEmit(LogRecord(body: 'two'));
      processor.onEmit(LogRecord(body: 'three'));

      expect(processor.queueLength, 2);
      await processor.forceFlush();
      expect(exporter.allRecords.map((r) => r.body), ['two', 'three']);
    });

    test('forceFlush drains everything currently buffered', () async {
      final processor = BatchLogRecordProcessor(
        exporter,
        resource,
        maxExportBatchSize: 100,
        scheduledDelay: const Duration(minutes: 10),
      );
      addTearDown(processor.shutdown);

      processor.onEmit(LogRecord(body: 'one'));
      processor.onEmit(LogRecord(body: 'two'));
      await processor.forceFlush();

      expect(processor.queueLength, 0);
      expect(exporter.allRecords, hasLength(2));
    });

    test('periodic timer flushes on schedule without an explicit forceFlush',
        () async {
      final processor = BatchLogRecordProcessor(
        exporter,
        resource,
        maxExportBatchSize: 100,
        scheduledDelay: const Duration(milliseconds: 20),
      );
      addTearDown(processor.shutdown);

      processor.onEmit(LogRecord(body: 'one'));
      expect(exporter.exportedBatches, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(exporter.allRecords.map((r) => r.body), ['one']);
    });

    test('shutdown flushes remaining records and stops the timer', () async {
      final processor = BatchLogRecordProcessor(
        exporter,
        resource,
        maxExportBatchSize: 100,
        scheduledDelay: const Duration(milliseconds: 20),
      );

      processor.onEmit(LogRecord(body: 'one'));
      await processor.shutdown();

      expect(exporter.allRecords.map((r) => r.body), ['one']);
      expect(exporter.shutdownCallCount, 1);

      // Further emits after shutdown are dropped, not queued or exported.
      processor.onEmit(LogRecord(body: 'two'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(exporter.allRecords.map((r) => r.body), ['one']);
    });

    test('swallows a failed export instead of throwing', () async {
      exporter.nextResult = const ExportResult.failure('boom');
      final processor = BatchLogRecordProcessor(
        exporter,
        resource,
        maxExportBatchSize: 100,
        scheduledDelay: const Duration(minutes: 10),
      );
      addTearDown(processor.shutdown);

      processor.onEmit(LogRecord(body: 'one'));

      await expectLater(processor.forceFlush(), completes);
    });

    test('throws ArgumentError for a non-positive maxQueueSize', () {
      expect(
        () => BatchLogRecordProcessor(exporter, resource, maxQueueSize: 0),
        throwsArgumentError,
      );
      expect(
        () => BatchLogRecordProcessor(exporter, resource, maxQueueSize: -1),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for a non-positive maxExportBatchSize', () {
      expect(
        () =>
            BatchLogRecordProcessor(exporter, resource, maxExportBatchSize: 0),
        throwsArgumentError,
      );
      expect(
        () => BatchLogRecordProcessor(
          exporter,
          resource,
          maxExportBatchSize: -5,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for a non-positive scheduledDelay', () {
      expect(
        () => BatchLogRecordProcessor(
          exporter,
          resource,
          scheduledDelay: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => BatchLogRecordProcessor(
          exporter,
          resource,
          scheduledDelay: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    });
  });
}
