import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('formatTraceparent', () {
    test('formats version-flags-traceId-spanId with sampled always set', () {
      const context = SpanContext(
        traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
        spanId: '00f067aa0ba902b7',
      );
      expect(
        formatTraceparent(context),
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
      );
    });
  });

  group('parseTraceparent', () {
    test('round-trips a formatted header back to an equivalent SpanContext',
        () {
      const original = SpanContext(
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
      );
      final parsed = parseTraceparent(formatTraceparent(original));

      expect(parsed, isNotNull);
      expect(parsed!.traceId, original.traceId);
      expect(parsed.spanId, original.spanId);
    });

    test('parses a remote context and marks it as such', () {
      final parsed = parseTraceparent(
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
      );
      expect(parsed, isNotNull);
      expect(parsed!.isRemote, isTrue);
    });

    test('parses the W3C spec\'s own example header', () {
      // https://www.w3.org/TR/trace-context/#examples-of-http-traceparent-headers
      final parsed = parseTraceparent(
        '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01',
      );
      expect(parsed, isNotNull);
      expect(parsed!.traceId, '0af7651916cd43dd8448eb211c80319c');
      expect(parsed.spanId, 'b7ad6b7169203331');
    });

    test('returns null for a null header', () {
      expect(parseTraceparent(null), isNull);
    });

    test('returns null for an empty header', () {
      expect(parseTraceparent(''), isNull);
    });

    test('returns null when the segment count is wrong', () {
      expect(
        parseTraceparent('00-4bf92f3577b34da6a3ce929d0e0e4736-01'),
        isNull,
      );
    });

    test('returns null when the trace ID length is wrong', () {
      expect(
        parseTraceparent('00-4bf92f3577b34da6a3ce929d0e0e-00f067aa0ba902b7-01'),
        isNull,
      );
    });

    test('returns null when the span ID length is wrong', () {
      expect(
        parseTraceparent(
          '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902-01',
        ),
        isNull,
      );
    });

    test('returns null when a segment has non-hex characters', () {
      expect(
        parseTraceparent(
          '00-zzf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
        ),
        isNull,
      );
    });

    test('returns null for the reserved version "ff"', () {
      expect(
        parseTraceparent(
          'ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
        ),
        isNull,
      );
    });

    test('returns null for an all-zero trace ID', () {
      expect(
        parseTraceparent(
          '00-00000000000000000000000000000000-00f067aa0ba902b7-01',
        ),
        isNull,
      );
    });

    test('returns null for an all-zero span ID', () {
      expect(
        parseTraceparent(
          '00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01',
        ),
        isNull,
      );
    });

    test('returns null for a version-00 header with trailing garbage', () {
      // Version 00 is not forward-compatible: it must be exactly the
      // 4-field shape, nothing appended.
      expect(
        parseTraceparent(
          '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-extra',
        ),
        isNull,
      );
    });

    test(
        'parses a version-01+ header with valid known fields plus trailing '
        'extra fields', () {
      final parsed = parseTraceparent(
        '01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-rojo-something',
      );
      expect(parsed, isNotNull);
      expect(parsed!.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(parsed.spanId, '00f067aa0ba902b7');
      expect(parsed.isRemote, isTrue);
    });

    test(
        'parses a version-fe header (highest non-reserved version) with '
        'extra fields', () {
      final parsed = parseTraceparent(
        'fe-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00-extra-more',
      );
      expect(parsed, isNotNull);
      expect(parsed!.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(parsed.spanId, '00f067aa0ba902b7');
    });

    test(
        'returns null for the reserved version "ff" even with no trailing '
        'fields', () {
      expect(
        parseTraceparent(
          'ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
        ),
        isNull,
      );
    });

    test('returns null for the reserved version "ff" with trailing fields', () {
      expect(
        parseTraceparent(
          'ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-extra',
        ),
        isNull,
      );
    });
  });
}
