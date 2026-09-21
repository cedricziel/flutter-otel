import 'package:dart_otel_sdk/dart_otel_sdk.dart';
import 'package:test/test.dart';

import 'support/fake_span_exporter.dart';

void main() {
  late FakeSpanExporter exporter;
  late OTelResource resource;
  late SimpleSpanProcessor processor;
  late SdkTracer tracer;

  setUp(() {
    exporter = FakeSpanExporter();
    resource = OTelResource(serviceName: 'test');
    processor = SimpleSpanProcessor(exporter, resource);
    tracer =
        SdkTracer(name: 'my.tracer', version: '1.0.0', processor: processor);
  });

  group('SdkTracer.startSpan parent resolution', () {
    test(
        'is a root span (no parent) when nothing is active and no explicit '
        'parentContext is given', () {
      final span = tracer.startSpan('op') as SdkSpan;
      expect(span.parentSpanId, isNull);
    });

    test('uses the explicit parentContext over any ambient span', () async {
      const explicitParent = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
      );

      await tracer.startActiveSpan('ambient', (ambientSpan) async {
        final span = tracer.startSpan(
          'child',
          parentContext: explicitParent,
        ) as SdkSpan;

        expect(span.spanContext.traceId, explicitParent.traceId);
        expect(span.parentSpanId, explicitParent.spanId);
        expect(span.parentSpanId, isNot(ambientSpan.spanContext.spanId));
        return null;
      });
    });

    test(
        'falls back to Span.current when no explicit parentContext is '
        'given', () async {
      await tracer.startActiveSpan('parent', (parentSpan) async {
        final child = tracer.startSpan('child') as SdkSpan;

        expect(child.spanContext.traceId, parentSpan.spanContext.traceId);
        expect(child.parentSpanId, parentSpan.spanContext.spanId);
        return null;
      });
    });

    test('stamps the tracer\'s own name/version as the span\'s scope',
        () async {
      final span = tracer.startSpan('op');
      span.end();
      await processor.forceFlush();

      final data = exporter.allSpans.single;
      expect(data.scopeName, 'my.tracer');
      expect(data.scopeVersion, '1.0.0');
    });
  });

  group('SdkTracer links', () {
    test('startSpan carries links through to the exported SpanData', () async {
      const linkedContext = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      final span = tracer.startSpan(
        'op',
        links: [
          SpanLink(linkedContext, attributes: {'ws.connection.id': 'c1'}),
        ],
      );
      span.end();
      await processor.forceFlush();

      final data = exporter.allSpans.single;
      expect(data.links, hasLength(1));
      expect(data.links.single.context, linkedContext);
      expect(data.links.single.attributes, {'ws.connection.id': 'c1'});
    });

    test('startSpan defaults to no links', () async {
      final span = tracer.startSpan('op');
      span.end();
      await processor.forceFlush();

      expect(exporter.allSpans.single.links, isEmpty);
    });

    test('a linked root span is not nested under the linked span', () {
      const linkedContext = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      final span = tracer.startSpan(
        'op',
        links: [SpanLink(linkedContext)],
      ) as SdkSpan;

      expect(span.parentSpanId, isNull);
      expect(span.spanContext.traceId, isNot(linkedContext.traceId));
    });
  });

  group('SdkTracer.startActiveSpan', () {
    test('makes the span Span.current for the duration of body', () async {
      Span? observed;
      await tracer.startActiveSpan('op', (span) async {
        observed = Span.current;
      });

      expect(observed, isNotNull);
      expect(Span.current, isNull);
    });

    test('nested startActiveSpan calls chain parent/child correctly', () async {
      SpanContext? outerContext;
      SpanContext? innerContext;

      await tracer.startActiveSpan('outer', (outer) async {
        outerContext = outer.spanContext;
        await tracer.startActiveSpan('inner', (inner) async {
          innerContext = inner.spanContext;
        });
        // The outer span is current again once the inner one completes.
        expect(Span.current, same(outer));
      });

      expect(innerContext!.traceId, outerContext!.traceId);
    });

    test('ends the span and returns body\'s result on success', () async {
      final result = await tracer.startActiveSpan('op', (span) async {
        expect(span.isRecording, isTrue);
        return 7;
      });
      await processor.forceFlush();

      expect(result, 7);
      expect(exporter.allSpans, hasLength(1));
      expect(exporter.allSpans.single.statusCode, StatusCode.unset);
    });

    test(
        'records the exception, sets an error status, ends the span, and '
        'rethrows when body throws', () async {
      await expectLater(
        tracer.startActiveSpan<void>('op', (span) async {
          throw StateError('boom');
        }),
        throwsStateError,
      );
      await processor.forceFlush();

      final data = exporter.allSpans.single;
      expect(data.statusCode, StatusCode.error);
      expect(data.statusDescription, contains('boom'));
      expect(data.events.single.name, 'exception');
      expect(data.events.single.attributes['exception.type'],
          contains('StateError'));
    });
  });
}
