import 'package:dart_otel_api/dart_otel_api.dart';

import 'redactor.dart';

/// A [SpanProcessor] that redacts a finished span's attributes, event and
/// link attributes and status description, then forwards the redacted copy
/// to [next].
///
/// [SpanData] is an immutable snapshot taken at [Span.end], so this rewrites
/// the copy handed to exporters and never the live span. Span and event
/// names are left alone: they name operations, not data.
class RedactingSpanProcessor implements SpanProcessor {
  RedactingSpanProcessor(this.next, this.redactor);

  final SpanProcessor next;
  final Redactor redactor;

  @override
  void onEnd(SpanData span) {
    final description = span.statusDescription;
    next.onEnd(
      SpanData(
        name: span.name,
        spanContext: span.spanContext,
        parentSpanId: span.parentSpanId,
        kind: span.kind,
        startTime: span.startTime,
        endTime: span.endTime,
        attributes: redactAttributes(span.attributes, redactor),
        events: [
          for (final event in span.events)
            SpanEvent(
              name: event.name,
              timestamp: event.timestamp,
              attributes: redactAttributes(event.attributes, redactor),
            ),
        ],
        links: [
          for (final link in span.links)
            SpanLink(
              link.context,
              attributes: redactAttributes(link.attributes, redactor),
            ),
        ],
        statusCode: span.statusCode,
        statusDescription:
            description == null ? null : redactor.redact(description),
        scopeName: span.scopeName,
        scopeVersion: span.scopeVersion,
      ),
    );
  }

  @override
  Future<void> forceFlush() => next.forceFlush();

  @override
  Future<void> shutdown() => next.shutdown();
}
