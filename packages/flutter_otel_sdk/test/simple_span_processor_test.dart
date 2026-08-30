import 'package:flutter_otel_sdk/flutter_otel_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

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
  late SimpleSpanProcessor processor;

  setUp(() {
    exporter = FakeSpanExporter();
    resource = OTelResource(serviceName: 'test');
    processor = SimpleSpanProcessor(exporter, resource);
  });

  group('SimpleSpanProcessor', () {
    test('forwards each ended span to the exporter immediately', () async {
      processor.onEnd(_span('one'));
      await processor.forceFlush();

      expect(exporter.exportedBatches, hasLength(1));
      expect(exporter.exportedBatches.single, hasLength(1));
      expect(exporter.exportedBatches.single.single.name, 'one');
      expect(exporter.resources.single, resource);
    });

    test('exports each span as its own batch, not merged together', () async {
      processor.onEnd(_span('one'));
      processor.onEnd(_span('two'));
      await processor.forceFlush();

      expect(exporter.exportedBatches, hasLength(2));
      expect(exporter.allSpans.map((s) => s.name), ['one', 'two']);
    });

    test('forceFlush waits for in-flight exports to complete', () async {
      exporter.gate = null;
      processor.onEnd(_span('one'));

      await processor.forceFlush();

      expect(exporter.exportedBatches, hasLength(1));
    });

    test('swallows a failed export instead of throwing', () async {
      exporter.nextResult = const ExportResult.failure('boom');
      processor.onEnd(_span('one'));

      await expectLater(processor.forceFlush(), completes);
    });

    test('shutdown flushes pending spans and shuts down the exporter',
        () async {
      processor.onEnd(_span('one'));
      await processor.shutdown();

      expect(exporter.exportedBatches, hasLength(1));
      expect(exporter.shutdownCallCount, 1);
    });

    test('onEnd after shutdown is a no-op and never touches the exporter',
        () async {
      processor.onEnd(_span('one'));
      await processor.shutdown();

      expect(exporter.exportedBatches, hasLength(1));

      processor.onEnd(_span('two'));
      await Future<void>.delayed(Duration.zero);

      // Still just the one span exported before shutdown; the post-shutdown
      // onEnd was dropped rather than exported through a released exporter.
      expect(exporter.exportedBatches, hasLength(1));
      expect(exporter.allSpans.map((s) => s.name), ['one']);
    });
  });
}
