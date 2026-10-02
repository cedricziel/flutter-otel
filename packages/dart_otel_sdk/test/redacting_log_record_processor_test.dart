import 'package:dart_otel_sdk/dart_otel_sdk.dart';
import 'package:test/test.dart';

class _RecordingProcessor implements LogRecordProcessor {
  final List<LogRecord> emitted = [];
  int flushCount = 0;
  int shutdownCount = 0;

  @override
  void onEmit(LogRecord record) => emitted.add(record);

  @override
  Future<void> forceFlush() async => flushCount++;

  @override
  Future<void> shutdown() async => shutdownCount++;
}

void main() {
  group('RedactingLogRecordProcessor', () {
    late _RecordingProcessor next;
    late RedactingLogRecordProcessor processor;

    setUp(() {
      next = _RecordingProcessor();
      processor = RedactingLogRecordProcessor(next, PatternRedactor());
    });

    test('redacts the body and string attributes before forwarding', () {
      processor.onEmit(
        LogRecord(
          body: 'auth failed: password=hunter2',
          attributes: {
            'exception.message': 'Bearer abc123',
            'exception.stacktrace': '#0 login (password=hunter2)',
            'retry.count': 3,
          },
        ),
      );

      final forwarded = next.emitted.single;
      expect(forwarded.body, 'auth failed: password=[REDACTED]');
      expect(forwarded.attributes['exception.message'], 'Bearer [REDACTED]');
      expect(
        forwarded.attributes['exception.stacktrace'],
        '#0 login (password=[REDACTED])',
      );
      expect(forwarded.attributes['retry.count'], 3);
    });

    test('replaces the whole value of sensitive attribute keys', () {
      processor.onEmit(
        LogRecord(
          body: 'request',
          attributes: {
            'http.request.header.authorization': 'opaque-token-without-prefix',
            'tags': ['ok', 'password=x'],
          },
        ),
      );

      final attributes = next.emitted.single.attributes;
      expect(attributes['http.request.header.authorization'], '[REDACTED]');
      expect(attributes['tags'], ['ok', 'password=[REDACTED]']);
    });

    test('keeps every other field of the record', () {
      final original = LogRecord(
        body: 'plain',
        severity: LogSeverity.warn,
        timestamp: DateTime.utc(2026, 1, 2),
        observedTimestamp: DateTime.utc(2026, 1, 3),
        traceId: 'aaaa',
        spanId: 'bbbb',
        scopeName: 'truehub.api',
        scopeVersion: '1.0.0',
      );

      processor.onEmit(original);

      final forwarded = next.emitted.single;
      expect(forwarded.severity, LogSeverity.warn);
      expect(forwarded.timestamp, original.timestamp);
      expect(forwarded.observedTimestamp, original.observedTimestamp);
      expect(forwarded.traceId, 'aaaa');
      expect(forwarded.spanId, 'bbbb');
      expect(forwarded.scopeName, 'truehub.api');
      expect(forwarded.scopeVersion, '1.0.0');
    });

    test('forwards flush and shutdown', () async {
      await processor.forceFlush();
      await processor.shutdown();

      expect(next.flushCount, 1);
      expect(next.shutdownCount, 1);
    });
  });
}
