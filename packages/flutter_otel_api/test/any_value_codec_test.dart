import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('encodeAnyValue', () {
    test('encodes String as stringValue', () {
      expect(encodeAnyValue('hi'), {'stringValue': 'hi'});
    });

    test('encodes bool as boolValue', () {
      expect(encodeAnyValue(true), {'boolValue': true});
      expect(encodeAnyValue(false), {'boolValue': false});
    });

    test('encodes int as intValue string', () {
      expect(encodeAnyValue(42), {'intValue': '42'});
    });

    test('encodes double as doubleValue', () {
      expect(encodeAnyValue(1.5), {'doubleValue': 1.5});
    });

    test('falls back to stringValue via toString for anything else', () {
      final result = encodeAnyValue(<int>[1, 2, 3]);
      expect(result, {'stringValue': '[1, 2, 3]'});
    });

    test('falls back to stringValue for null', () {
      expect(encodeAnyValue(null), {'stringValue': 'null'});
    });
  });

  group('encodeAttributes', () {
    test('encodes an attribute map as a repeated KeyValue list', () {
      final encoded = encodeAttributes({
        'service.name': 'trueapp',
        'retry.count': 3,
      });
      expect(encoded, [
        {
          'key': 'service.name',
          'value': {'stringValue': 'trueapp'},
        },
        {
          'key': 'retry.count',
          'value': {'intValue': '3'},
        },
      ]);
    });

    test('returns an empty list for empty attributes', () {
      expect(encodeAttributes(const {}), isEmpty);
    });
  });
}
