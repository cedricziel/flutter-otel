import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('LogRecord defaults', () {
    test('defaults severity to info and timestamp to now', () {
      final before = DateTime.now();
      final record = LogRecord(body: 'hello');
      final after = DateTime.now();

      expect(record.severity, LogSeverity.info);
      expect(
        record.timestamp.isAfter(before) ||
            record.timestamp.isAtSameMomentAs(before),
        isTrue,
      );
      expect(
        record.timestamp.isBefore(after) ||
            record.timestamp.isAtSameMomentAs(after),
        isTrue,
      );
    });

    test('defaults observedTimestamp to timestamp when not given', () {
      final ts = DateTime(2026, 1, 1);
      final record = LogRecord(body: 'hello', timestamp: ts);
      expect(record.observedTimestamp, ts);
    });

    test('defaults attributes to an empty, unmodifiable map', () {
      final record = LogRecord(body: 'hello');
      expect(record.attributes, isEmpty);
      expect(() => record.attributes['x'] = 'y', throwsUnsupportedError);
    });

    test('defaults traceId/spanId to null', () {
      final record = LogRecord(body: 'hello');
      expect(record.traceId, isNull);
      expect(record.spanId, isNull);
    });

    test('defaults scopeName to flutter_otel and scopeVersion to null', () {
      final record = LogRecord(body: 'hello');
      expect(record.scopeName, 'flutter_otel');
      expect(record.scopeVersion, isNull);
    });

    test('accepts explicit traceId/spanId for future trace correlation', () {
      final record = LogRecord(
        body: 'hello',
        traceId: 'abc123',
        spanId: 'def456',
      );
      expect(record.traceId, 'abc123');
      expect(record.spanId, 'def456');
    });
  });

  group('LogRecord.withAttributes', () {
    test('merges new attributes without mutating the original', () {
      final original = LogRecord(
        body: 'hello',
        attributes: {'a': 1},
      );
      final enriched = original.withAttributes({'b': 2});

      expect(original.attributes, {'a': 1});
      expect(enriched.attributes, {'a': 1, 'b': 2});
    });

    test('existing attributes win over the merged-in ones on key conflict', () {
      final original = LogRecord(
        body: 'hello',
        attributes: {'session.id': 'explicit-session'},
      );
      final enriched = original.withAttributes({'session.id': 'auto-session'});

      expect(enriched.attributes['session.id'], 'explicit-session');
    });

    test('preserves severity, timestamps, traceId/spanId, and scope', () {
      final ts = DateTime(2026, 1, 1);
      final original = LogRecord(
        body: 'hello',
        severity: LogSeverity.error,
        timestamp: ts,
        traceId: 'trace',
        spanId: 'span',
        scopeName: 'my.scope',
        scopeVersion: '2.0.0',
      );
      final enriched = original.withAttributes({'x': 1});

      expect(enriched.severity, LogSeverity.error);
      expect(enriched.timestamp, ts);
      expect(enriched.observedTimestamp, ts);
      expect(enriched.traceId, 'trace');
      expect(enriched.spanId, 'span');
      expect(enriched.scopeName, 'my.scope');
      expect(enriched.scopeVersion, '2.0.0');
    });
  });

  group('LogRecord.withScope', () {
    test('returns a copy stamped with the given scope', () {
      final original = LogRecord(body: 'hello', attributes: {'a': 1});
      final scoped = original.withScope('my.logger', '1.0.0');

      expect(scoped.scopeName, 'my.logger');
      expect(scoped.scopeVersion, '1.0.0');
      expect(scoped.attributes, original.attributes);
      expect(scoped.body, original.body);
    });
  });
}
