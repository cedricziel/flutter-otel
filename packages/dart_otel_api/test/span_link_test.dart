import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('SpanLink', () {
    const context = SpanContext(
      traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      spanId: 'bbbbbbbbbbbbbbbb',
    );

    test('defaults to empty attributes', () {
      final link = SpanLink(context);
      expect(link.context, context);
      expect(link.attributes, isEmpty);
    });

    test('attributes are unmodifiable', () {
      final link = SpanLink(context, attributes: {'k': 'v'});
      expect(() => link.attributes['k2'] = 'v2', throwsUnsupportedError);
    });

    test('toString includes context and attributes', () {
      final link = SpanLink(context, attributes: {'k': 'v'});
      expect(link.toString(), contains(context.toString()));
      expect(link.toString(), contains('k'));
    });
  });
}
