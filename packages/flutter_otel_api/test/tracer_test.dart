import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('Span.current', () {
    test('is null when no span is active', () {
      expect(Span.current, isNull);
    });

    test('runWithSpan makes a span current only for the duration of body',
        () async {
      final tracer = const NoopTracer('test');
      final span = tracer.startSpan('outer');

      Span? observedInside;
      await Span.runWithSpan(span, () async {
        observedInside = Span.current;
        return null;
      });

      expect(observedInside, same(span));
      expect(Span.current, isNull);
    });

    test('stays current across an await gap inside body', () async {
      final tracer = const NoopTracer('test');
      final span = tracer.startSpan('outer');

      Span? observedAfterAwait;
      await Span.runWithSpan(span, () async {
        await Future<void>.delayed(Duration.zero);
        observedAfterAwait = Span.current;
      });

      expect(observedAfterAwait, same(span));
    });

    test('nesting restores the outer span once the inner one completes',
        () async {
      final tracer = const NoopTracer('test');
      final outer = tracer.startSpan('outer');
      final inner = tracer.startSpan('inner');

      Span? observedInInner;
      Span? observedAfterInner;
      await Span.runWithSpan(outer, () async {
        await Span.runWithSpan(inner, () async {
          observedInInner = Span.current;
        });
        observedAfterInner = Span.current;
      });

      expect(observedInInner, same(inner));
      expect(observedAfterInner, same(outer));
    });
  });

  group('NoopTracer', () {
    test('startSpan returns a non-recording span with an invalid context', () {
      final tracer = const NoopTracer('test');
      final span = tracer.startSpan('op');

      expect(span.name, 'op');
      expect(span.isRecording, isFalse);
      expect(span.spanContext.isValid, isFalse);

      // Mutating a no-op span never throws.
      span.setAttribute('k', 'v');
      span.setAttributes({'k2': 'v2'});
      span.addEvent('evt');
      span.setStatus(StatusCode.error, description: 'boom');
      span.recordException(Exception('x'));
      span.end();
    });

    test(
        'startActiveSpan makes the span current for body and returns its '
        'result', () async {
      final tracer = const NoopTracer('test');
      final result = await tracer.startActiveSpan('op', (span) async {
        expect(Span.current, same(span));
        return 42;
      });

      expect(result, 42);
      expect(Span.current, isNull);
    });

    test('startActiveSpan rethrows an exception from body', () async {
      final tracer = const NoopTracer('test');

      await expectLater(
        tracer.startActiveSpan<void>('op', (span) async {
          throw StateError('boom');
        }),
        throwsStateError,
      );
    });
  });

  group('NoopTracerProvider', () {
    test('getTracer returns a NoopTracer carrying the requested name', () {
      const provider = NoopTracerProvider();
      final tracer = provider.getTracer(name: 'my.tracer');

      expect(tracer, isA<NoopTracer>());
      expect(tracer.name, 'my.tracer');
    });

    test('forceFlush and shutdown complete without error', () async {
      const provider = NoopTracerProvider();
      await expectLater(provider.forceFlush(), completes);
      await expectLater(provider.shutdown(), completes);
    });
  });
}
