import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('httpRequestHeaderAttributes', () {
    test('names attributes per the http semantic conventions', () {
      final attrs = httpRequestHeaderAttributes({
        'Content-Type': 'application/json',
        'X-Request-Id': 'abc',
      });

      expect(attrs, {
        'http.request.header.content_type': ['application/json'],
        'http.request.header.x_request_id': ['abc'],
      });
    });

    test('redacts sensitive headers instead of dropping them', () {
      final attrs = httpRequestHeaderAttributes({
        'Authorization': 'Bearer secret',
        'Cookie': 'sid=1',
        'X-Api-Key': 'k',
        'X-Auth-Token': 't',
        'Proxy-Authorization': 'Basic x',
      });

      expect(attrs.values, everyElement([redactedHttpHeaderValue]));
      expect(attrs.keys, hasLength(5));
    });

    test('accepts a custom redaction predicate', () {
      final attrs = httpRequestHeaderAttributes({
        'x-tenant': 'acme',
        'accept': '*/*',
      }, redact: (name) => name == 'x-tenant');

      expect(attrs['http.request.header.x_tenant'], [redactedHttpHeaderValue]);
      expect(attrs['http.request.header.accept'], ['*/*']);
    });

    test('is empty for no headers', () {
      expect(httpRequestHeaderAttributes({}), isEmpty);
    });
  });

  group('httpResponseHeaderAttributes', () {
    test('uses the response prefix and redacts set-cookie', () {
      final attrs = httpResponseHeaderAttributes({
        'Content-Length': '12',
        'Set-Cookie': 'sid=1; HttpOnly',
      });

      expect(attrs, {
        'http.response.header.content_length': ['12'],
        'http.response.header.set_cookie': [redactedHttpHeaderValue],
      });
    });
  });
}
