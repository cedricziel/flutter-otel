import 'package:flutter_otel_sdk/flutter_otel_sdk.dart';
import 'package:test/test.dart';

import 'support/fake_span_exporter.dart';

SpanData _span(String name) => SpanData(
      name: name,
      spanContext: SpanContext(
        traceId: generateTraceId(),
        spanId: generateSpanId(),
      ),
      startTime: DateTime.now(),
      endTime: DateTime.now(),
    );

void main() {
  late FakeSpanExporter exporter;
  late OTelResource resource;

  setUp(() {
    exporter = FakeSpanExporter();
    resource = OTelResource(serviceName: 'test');
  });

  group('BatchSpanProcessor', () {
    test('buffers spans without exporting until a threshold is reached',
        () async {
      final processor = BatchSpanProcessor(
        exporter,
        resource,
        maxExportBatchSize: 10,
        scheduledDelay: const Duration(minutes: 10),
      );
      addTearDown(processor.shutdown);

      processor.onEnd(_span('one'));
      // Give any stray microtasks a chance to run; there should be none.
      await Future<void>.delayed(Duration.zero);

      expect(exporter.exportedBatches, isEmpty);
      expect(processor.queueLength, 1);
    });

    test('automatically flushes once maxExportBatchSize is reached', () async {
      final processor = BatchSpanProcessor(
        exporter,
        resource,
        maxExportBatchSize: 2,
        scheduledDelay: const Duration(minutes: 10),
      );
      addTearDown(processor.shutdown);

      final exported = exporter.nextExport;
      processor.onEnd(_span('one'));
      processor.onEnd(_span('two'));
      // Await the processor's own automatic export triggered by onEnd
      // reaching maxExportBatchSize — not a forced flush — so a regression
      // that removes the auto-flush-on-threshold logic would actually fail
      // this test (it would otherwise hang and time out).
      await exported;

      expect(exporter.allSpans.map((s) => s.name), ['one', 'two']);
      expect(processor.queueLength, 0);
    });

    test('splits a large forced flush into batches of maxExportBatchSize',
        () async {
      final processor = BatchSpanProcessor(
        exporter,
        resource,
        maxExportBatchSize: 2,
        maxQueueSize: 100,
        scheduledDelay: const Duration(minutes: 10),
      );
      addTearDown(processor.shutdown);

      for (var i = 0; i < 5; i++) {
        processor.onEnd(_span('span-$i'));
      }
      await processor.forceFlush();

      // 5 spans at a batch size of 2 -> batches of [2, 2, 1].
      expect(exporter.exportedBatches.map((b) => b.length), [2, 2, 1]);
      expect(exporter.allSpans, hasLength(5));
    });

    test('drops the oldest span once maxQueueSize is exceeded', () async {
      final processor = BatchSpanProcessor(
        exporter,
        resource,
        maxQueueSize: 2,
        maxExportBatchSize: 100,
        scheduledDelay: const Duration(minutes: 10),
      );
      addTearDown(processor.shutdown);

      processor.onEnd(_span('one'));
      processor.onEnd(_span('two'));
      processor.onEnd(_span('three'));

      expect(processor.queueLength, 2);
      await processor.forceFlush();
      expect(exporter.allSpans.map((s) => s.name), ['two', 'three']);
    });

    test('forceFlush drains everything currently buffered', () async {
      final processor = BatchSpanProcessor(
        exporter,
        resource,
        maxExportBatchSize: 100,
        scheduledDelay: const Duration(minutes: 10),
      );
      addTearDown(processor.shutdown);

      processor.onEnd(_span('one'));
      processor.onEnd(_span('two'));
      await processor.forceFlush();

      expect(processor.queueLength, 0);
      expect(exporter.allSpans, hasLength(2));
    });

    test('periodic timer flushes on schedule without an explicit forceFlush',
        () async {
      final processor = BatchSpanProcessor(
        exporter,
        resource,
        maxExportBatchSize: 100,
        scheduledDelay: const Duration(milliseconds: 20),
      );
      addTearDown(processor.shutdown);

      processor.onEnd(_span('one'));
      expect(exporter.exportedBatches, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(exporter.allSpans.map((s) => s.name), ['one']);
    });

    test(
        'shutdown flushes remaining spans and stops the timer, and rejects '
        'the shutdown-race: no export starts during/after shutdown', () async {
      final processor = BatchSpanProcessor(
        exporter,
        resource,
        maxExportBatchSize: 100,
        scheduledDelay: const Duration(milliseconds: 20),
      );

      processor.onEnd(_span('one'));
      await processor.shutdown();

      expect(exporter.allSpans.map((s) => s.name), ['one']);
      expect(exporter.shutdownCallCount, 1);

      // Further onEnd calls after shutdown are dropped, not queued or
      // exported — this is the shutdown-race guard: `_shutdown` is set as
      // the first statement in shutdown() and checked at the top of
      // onEnd().
      processor.onEnd(_span('two'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(exporter.allSpans.map((s) => s.name), ['one']);
    });

    test('swallows a failed export instead of throwing', () async {
      exporter.nextResult = const ExportResult.failure('boom');
      final processor = BatchSpanProcessor(
        exporter,
        resource,
        maxExportBatchSize: 100,
        scheduledDelay: const Duration(minutes: 10),
      );
      addTearDown(processor.shutdown);

      processor.onEnd(_span('one'));

      await expectLater(processor.forceFlush(), completes);
    });

    test('throws ArgumentError for a non-positive maxQueueSize', () {
      expect(
        () => BatchSpanProcessor(exporter, resource, maxQueueSize: 0),
        throwsArgumentError,
      );
      expect(
        () => BatchSpanProcessor(exporter, resource, maxQueueSize: -1),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for a non-positive maxExportBatchSize', () {
      expect(
        () => BatchSpanProcessor(exporter, resource, maxExportBatchSize: 0),
        throwsArgumentError,
      );
      expect(
        () => BatchSpanProcessor(exporter, resource, maxExportBatchSize: -5),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for a non-positive scheduledDelay', () {
      expect(
        () => BatchSpanProcessor(
          exporter,
          resource,
          scheduledDelay: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => BatchSpanProcessor(
          exporter,
          resource,
          scheduledDelay: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    });
  });
}
