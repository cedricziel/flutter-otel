import 'package:flutter_otel_sdk/flutter_otel_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_span_exporter.dart';

void main() {
  late FakeSpanExporter exporter;
  late OTelResource resource;
  late SimpleSpanProcessor processor;

  setUp(() {
    exporter = FakeSpanExporter();
    resource = OTelResource(serviceName: 'test');
    processor = SimpleSpanProcessor(exporter, resource);
  });

  SdkSpan buildSpan({
    String name = 'op',
    SpanKind kind = SpanKind.internal,
    SpanContext? parentContext,
    String? parentSpanId,
  }) =>
      SdkSpan(
        name: name,
        kind: kind,
        parentContext: parentContext,
        parentSpanId: parentSpanId,
        processor: processor,
      );

  group('SdkSpan identity', () {
    test('generates a fresh, valid 32/16-hex trace/span ID for a root span',
        () {
      final span = buildSpan();

      expect(span.spanContext.traceId, hasLength(32));
      expect(span.spanContext.spanId, hasLength(16));
      expect(span.spanContext.isValid, isTrue);
      expect(span.parentSpanId, isNull);
    });

    test('two spans never collide on span ID', () {
      final a = buildSpan();
      final b = buildSpan();

      expect(a.spanContext.spanId, isNot(b.spanContext.spanId));
    });

    test('inherits the trace ID from an explicit parent context', () {
      const parent = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      final span =
          buildSpan(parentContext: parent, parentSpanId: 'bbbbbbbbbbbbbbbb');

      expect(span.spanContext.traceId, parent.traceId);
      expect(span.spanContext.spanId, isNot(parent.spanId));
      expect(span.parentSpanId, 'bbbbbbbbbbbbbbbb');
    });

    test('exposes the requested name and defaults to isRecording true', () {
      final span = buildSpan(name: 'my-op');
      expect(span.name, 'my-op');
      expect(span.isRecording, isTrue);
    });
  });

  group('SdkSpan attributes/events/status', () {
    test('setAttribute/setAttributes end up on the exported SpanData',
        () async {
      final span = buildSpan()
        ..setAttribute('a', 1)
        ..setAttributes({'b': 2, 'c': 3});
      span.end();
      await processor.forceFlush();

      final data = exporter.allSpans.single;
      expect(data.attributes, {'a': 1, 'b': 2, 'c': 3});
    });

    test('addEvent records a SpanEvent with name/attributes', () async {
      final span = buildSpan()..addEvent('checkpoint', attributes: {'k': 'v'});
      span.end();
      await processor.forceFlush();

      final data = exporter.allSpans.single;
      expect(data.events, hasLength(1));
      expect(data.events.single.name, 'checkpoint');
      expect(data.events.single.attributes, {'k': 'v'});
    });

    test('setStatus is reflected on the exported SpanData', () async {
      final span = buildSpan()..setStatus(StatusCode.ok, description: 'done');
      span.end();
      await processor.forceFlush();

      final data = exporter.allSpans.single;
      expect(data.statusCode, StatusCode.ok);
      expect(data.statusDescription, 'done');
    });

    test('defaults to StatusCode.unset', () async {
      final span = buildSpan();
      span.end();
      await processor.forceFlush();

      expect(exporter.allSpans.single.statusCode, StatusCode.unset);
    });

    test(
        'recordException adds an exception event with semantic-convention '
        'attributes', () async {
      final span = buildSpan();
      span.recordException(
        StateError('boom'),
        stackTrace: StackTrace.current,
        attributes: {'extra': 'x'},
      );
      span.end();
      await processor.forceFlush();

      final event = exporter.allSpans.single.events.single;
      expect(event.name, 'exception');
      expect(event.attributes['exception.type'], contains('StateError'));
      expect(event.attributes['exception.message'], contains('boom'));
      expect(event.attributes['exception.stacktrace'], isNotEmpty);
      expect(event.attributes['extra'], 'x');
    });

    test('mutations after end() are silently ignored', () async {
      final span = buildSpan();
      span.end();

      span.setAttribute('late', 'value');
      span.setStatus(StatusCode.error);
      span.addEvent('too-late');

      await processor.forceFlush();

      final data = exporter.allSpans.single;
      expect(data.attributes.containsKey('late'), isFalse);
      expect(data.statusCode, StatusCode.unset);
      expect(data.events, isEmpty);
    });
  });

  group('SdkSpan.end', () {
    test('isRecording becomes false after end()', () {
      final span = buildSpan();
      expect(span.isRecording, isTrue);
      span.end();
      expect(span.isRecording, isFalse);
    });

    test('calling end() a second time is a safe no-op', () async {
      final span = buildSpan();
      span.end();
      span.end();
      span.end();
      await processor.forceFlush();

      // Only one SpanData was ever handed to the processor.
      expect(exporter.allSpans, hasLength(1));
    });

    test('uses the given endTime when provided', () async {
      final span = buildSpan();
      final endTime = DateTime.utc(2026, 1, 1);
      span.end(endTime);
      await processor.forceFlush();

      expect(exporter.allSpans.single.endTime, endTime);
    });
  });
}
