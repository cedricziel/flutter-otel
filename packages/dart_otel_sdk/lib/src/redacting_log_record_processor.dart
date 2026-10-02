import 'package:dart_otel_api/dart_otel_api.dart';

import 'redactor.dart';

/// A [LogRecordProcessor] that redacts each record's body and attributes,
/// then forwards the redacted copy to [next].
///
/// Put it in front of the exporting processor so nothing leaves the process
/// unredacted, e.g.
/// `RedactingLogRecordProcessor(BatchLogRecordProcessor(...), PatternRedactor())`.
class RedactingLogRecordProcessor implements LogRecordProcessor {
  RedactingLogRecordProcessor(this.next, this.redactor);

  final LogRecordProcessor next;
  final Redactor redactor;

  @override
  void onEmit(LogRecord record) => next.onEmit(
        LogRecord(
          body: redactor.redact(record.body),
          severity: record.severity,
          timestamp: record.timestamp,
          observedTimestamp: record.observedTimestamp,
          attributes: redactAttributes(record.attributes, redactor),
          traceId: record.traceId,
          spanId: record.spanId,
          scopeName: record.scopeName,
          scopeVersion: record.scopeVersion,
        ),
      );

  @override
  Future<void> forceFlush() => next.forceFlush();

  @override
  Future<void> shutdown() => next.shutdown();
}
