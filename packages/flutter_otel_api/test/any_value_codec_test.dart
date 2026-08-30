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
      final result = encodeAnyValue(Object());
      expect(result, {'stringValue': result['stringValue']});
    });

    test('encodes null as an empty AnyValue', () {
      expect(encodeAnyValue(null), <String, Object?>{});
    });

    test('encodes a List as arrayValue.values, recursively', () {
      final result = encodeAnyValue(<Object?>[1, 'two', true, null]);
      expect(result, {
        'arrayValue': {
          'values': [
            {'intValue': '1'},
            {'stringValue': 'two'},
            {'boolValue': true},
            <String, Object?>{},
          ],
        },
      });
    });

    test('encodes nested Lists recursively', () {
      final result = encodeAnyValue(<Object?>[
        <Object?>[1, 2],
      ]);
      expect(result, {
        'arrayValue': {
          'values': [
            {
              'arrayValue': {
                'values': [
                  {'intValue': '1'},
                  {'intValue': '2'},
                ],
              },
            },
          ],
        },
      });
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

    test('encodes a null attribute as an empty AnyValue', () {
      final encoded = encodeAttributes({'nullable.attr': null});
      expect(encoded, [
        {'key': 'nullable.attr', 'value': <String, Object?>{}},
      ]);
    });

    test('encodes a list attribute as arrayValue.values', () {
      final encoded = encodeAttributes({
        'list.attr': <Object?>['a', 'b'],
      });
      expect(encoded, [
        {
          'key': 'list.attr',
          'value': {
            'arrayValue': {
              'values': [
                {'stringValue': 'a'},
                {'stringValue': 'b'},
              ],
            },
          },
        },
      ]);
    });
  });
}
