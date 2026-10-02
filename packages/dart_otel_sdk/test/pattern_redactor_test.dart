import 'package:dart_otel_sdk/dart_otel_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('PatternRedactor with default rules', () {
    final redactor = PatternRedactor();

    test('leaves text without secrets unchanged', () {
      const text = 'Connection to 192.168.1.10 timed out after 30s';
      expect(redactor.redact(text), text);
    });

    test('redacts bearer and basic credentials', () {
      expect(
        redactor.redact('header Authorization: Bearer abc.DEF-123_xyz='),
        'header Authorization: [REDACTED]',
      );
      expect(
        redactor.redact('sent Basic dXNlcjpwYXNz'),
        'sent Basic [REDACTED]',
      );
    });

    test('redacts secret key/value pairs, keeping the key', () {
      expect(
        redactor.redact('login failed: password=hunter2 user=root'),
        'login failed: password=[REDACTED] user=root',
      );
      expect(
        redactor.redact('{"api_key": "sk-123", "name": "nas"}'),
        '{"api_key": "[REDACTED]", "name": "nas"}',
      );
      expect(
        redactor.redact('token:abc123 secret = s3cr3t'),
        'token:[REDACTED] secret = [REDACTED]',
      );
    });

    test('redacts credentials embedded in URLs, keeping the host', () {
      expect(
        redactor.redact('GET https://admin:hunter2@nas.local/api/current'),
        'GET https://[REDACTED]@nas.local/api/current',
      );
    });

    test('does not treat an @ in the query or fragment as credentials', () {
      const query = 'https://nas.local:8080?next=user@example.com';
      const fragment = 'https://nas.local:8080/ui#user:x@example.com';

      expect(redactor.redact(query), query);
      expect(redactor.redact(fragment), fragment);
    });

    test('redacts every occurrence, not just the first', () {
      expect(
        redactor.redact('password=a then password=b'),
        'password=[REDACTED] then password=[REDACTED]',
      );
    });

    test('flags sensitive attribute keys regardless of case', () {
      expect(redactor.isSensitiveKey('Authorization'), isTrue);
      expect(redactor.isSensitiveKey('http.request.header.cookie'), isTrue);
      expect(redactor.isSensitiveKey('user.password'), isTrue);
      expect(redactor.isSensitiveKey('server.address'), isFalse);
      expect(redactor.isSensitiveKey('exception.message'), isFalse);
    });
  });

  group('PatternRedactor with extra rules', () {
    test('applies extra rules after the defaults', () {
      final redactor = PatternRedactor(
        extraRules: [RedactionRule(RegExp(r'\b\d{4}-\d{4}\b'))],
      );

      expect(
        redactor.redact('code 1234-5678 and password=x'),
        'code [REDACTED] and password=[REDACTED]',
      );
    });

    test('can replace the defaults entirely', () {
      final redactor = PatternRedactor(
        rules: [RedactionRule(RegExp('foo'), replacement: 'bar')],
        sensitiveKeys: const {},
      );

      expect(redactor.redact('foo password=x'), 'bar password=x');
      expect(redactor.isSensitiveKey('authorization'), isFalse);
    });
  });
}
