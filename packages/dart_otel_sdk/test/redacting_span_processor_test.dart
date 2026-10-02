import 'package:dart_otel_sdk/dart_otel_sdk.dart';
import 'package:test/test.dart';

class _RecordingProcessor implements SpanProcessor {
  final List<SpanData> ended = [];
  int flushCount = 0;
  int shutdownCount = 0;

  @override
  void onEnd(SpanData span) => ended.add(span);

  @override
  Future<void> forceFlush() async => flushCount++;

  @override
  Future<void> shutdown() async => shutdownCount++;
}

SpanData _span({
  String name = 'truenas.call',
  Map<String, Object?> attributes = const {},
  List<SpanEvent> events = const [],
  List<SpanLink> links = const [],
  String? statusDescription,
}) =>
    SpanData(
      name: name,
      spanContext: SpanContext(traceId: 'a' * 32, spanId: 'b' * 16),
      parentSpanId: 'c' * 16,
      kind: SpanKind.client,
      startTime: DateTime.utc(2026, 1, 1),
      endTime: DateTime.utc(2026, 1, 1, 0, 0, 1),
      attributes: attributes,
      events: events,
      links: links,
      statusCode: StatusCode.error,
      statusDescription: statusDescription,
      scopeName: 'truehub',
      scopeVersion: '1.0.0',
    );

void main() {
  group('RedactingSpanProcessor', () {
    late _RecordingProcessor next;
    late RedactingSpanProcessor processor;

    setUp(() {
      next = _RecordingProcessor();
      processor = RedactingSpanProcessor(next, PatternRedactor());
    });

    test('redacts attributes, exception events and status description', () {
      processor.onEnd(
        _span(
          attributes: {
            'url.full': 'https://root:pw@nas.local/api',
            'cookie': 'session=abc',
            'server.address': 'nas.local',
          },
          events: [
            SpanEvent(
              name: 'exception',
              timestamp: DateTime.utc(2026, 1, 1, 0, 0, 0, 500),
              attributes: {'exception.message': 'password=hunter2 rejected'},
            ),
          ],
          statusDescription: 'Bearer abc123 expired',
        ),
      );

      final forwarded = next.ended.single;
      expect(
        forwarded.attributes['url.full'],
        'https://[REDACTED]@nas.local/api',
      );
      expect(forwarded.attributes['cookie'], '[REDACTED]');
      expect(forwarded.attributes['server.address'], 'nas.local');
      expect(forwarded.events.single.name, 'exception');
      expect(
        forwarded.events.single.timestamp,
        DateTime.utc(2026, 1, 1, 0, 0, 0, 500),
      );
      expect(
        forwarded.events.single.attributes['exception.message'],
        'password=[REDACTED] rejected',
      );
      expect(forwarded.statusDescription, 'Bearer [REDACTED] expired');
    });

    test('redacts link attributes and keeps the linked context', () {
      final linked = SpanContext(traceId: 'd' * 32, spanId: 'e' * 16);
      processor.onEnd(
        _span(
          links: [
            SpanLink(linked, attributes: {'note': 'token=abc'}),
          ],
        ),
      );

      final link = next.ended.single.links.single;
      expect(link.context, linked);
      expect(link.attributes['note'], 'token=[REDACTED]');
    });

    test('keeps the span name and every structural field', () {
      final original = _span(name: 'truenas.connect');

      processor.onEnd(original);

      final forwarded = next.ended.single;
      expect(forwarded.name, 'truenas.connect');
      expect(forwarded.spanContext, original.spanContext);
      expect(forwarded.parentSpanId, original.parentSpanId);
      expect(forwarded.kind, SpanKind.client);
      expect(forwarded.startTime, original.startTime);
      expect(forwarded.endTime, original.endTime);
      expect(forwarded.statusCode, StatusCode.error);
      expect(forwarded.scopeName, 'truehub');
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
