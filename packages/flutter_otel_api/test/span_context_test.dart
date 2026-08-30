import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('SpanContext.isValid', () {
    test('a well-formed trace/span ID pair is valid', () {
      const context = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      expect(context.isValid, isTrue);
    });

    test('an all-zero trace ID is invalid', () {
      const context = SpanContext(
        traceId: '00000000000000000000000000000000',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      expect(context.isValid, isFalse);
    });

    test('an all-zero span ID is invalid', () {
      const context = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: '0000000000000000',
      );
      expect(context.isValid, isFalse);
    });

    test('a trace ID that is too short is invalid', () {
      const context = SpanContext(
        traceId: 'aaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      expect(context.isValid, isFalse);
    });

    test('a span ID that is too long is invalid', () {
      const context = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbbbb',
      );
      expect(context.isValid, isFalse);
    });

    test('uppercase hex is invalid (IDs must be lowercase)', () {
      const context = SpanContext(
        traceId: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      expect(context.isValid, isFalse);
    });

    test('non-hex characters are invalid', () {
      const context = SpanContext(
        traceId: 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      expect(context.isValid, isFalse);
    });
  });

  group('SpanContext.isRemote', () {
    test('defaults to false', () {
      const context = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      expect(context.isRemote, isFalse);
    });
  });

  group('SpanContext equality', () {
    test('two contexts with the same fields are equal', () {
      const a = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      const b = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing isRemote makes contexts unequal', () {
      const a = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      const b = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
        isRemote: true,
      );
      expect(a, isNot(b));
    });
  });
}
