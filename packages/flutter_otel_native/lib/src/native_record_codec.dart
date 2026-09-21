import 'dart:convert';

import 'package:dart_otel_api/dart_otel_api.dart';

/// One decoded line from the native queue: either a span or a log record.
sealed class NativeRecord {}

/// A decoded span line, ready to be fed into
/// `TracerProvider.ingestSpan`.
class NativeSpanRecord extends NativeRecord {
  NativeSpanRecord(this.spanData);

  final SpanData spanData;
}

/// A decoded log line, ready to be fed into
/// `LoggerProvider.ingestLogRecord`.
class NativeLogRecord extends NativeRecord {
  NativeLogRecord(this.logRecord);

  final LogRecord logRecord;
}

/// Decodes one NDJSON line produced by the native queue into a
/// [NativeRecord]. Returns `null` when the line is malformed — invalid
/// JSON, not a JSON object, an unrecognized `"kind"`, or missing a field
/// required for that kind — so callers can count and skip it rather than
/// crash the whole drain.
NativeRecord? decodeNativeRecordLine(String line) {
  try {
    final json = jsonDecode(line);
    if (json is! Map<String, Object?>) return null;
    switch (json['kind']) {
      case 'span':
        final spanData = _decodeSpanData(json);
        return spanData == null ? null : NativeSpanRecord(spanData);
      case 'log':
        final logRecord = _decodeLogRecord(json);
        return logRecord == null ? null : NativeLogRecord(logRecord);
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

/// Returns `null` when the trace/span identifiers or the parent span id are
/// missing, malformed, or the all-zero sentinel — see [SpanContext.isValid].
SpanData? _decodeSpanData(Map<String, Object?> json) {
  final spanContext = SpanContext(
    traceId: json['traceId']! as String,
    spanId: json['spanId']! as String,
  );
  if (!spanContext.isValid) return null;

  final parentSpanId = json['parentSpanId'] as String?;
  if (parentSpanId != null && !_isValidSpanId(parentSpanId)) return null;

  final eventsJson = (json['events'] as List?) ?? const [];
  return SpanData(
    name: json['name']! as String,
    spanContext: spanContext,
    parentSpanId: parentSpanId,
    kind: SpanKind.values.byName(json['spanKind']! as String),
    startTime: _dateTimeFromUnixNano(json['startTimeUnixNano']! as String),
    endTime: _dateTimeFromUnixNano(json['endTimeUnixNano']! as String),
    attributes:
        (json['attributes'] as Map?)?.cast<String, Object?>() ?? const {},
    events: eventsJson.cast<Map<String, Object?>>().map((event) {
      return SpanEvent(
        name: event['name']! as String,
        timestamp: _dateTimeFromUnixNano(event['timeUnixNano']! as String),
        attributes:
            (event['attributes'] as Map?)?.cast<String, Object?>() ?? const {},
      );
    }).toList(),
    statusCode: StatusCode.values.byName(json['statusCode']! as String),
    statusDescription: json['statusDescription'] as String?,
    scopeName: json['scopeName'] as String? ?? defaultInstrumentationScopeName,
    scopeVersion: json['scopeVersion'] as String?,
  );
}

/// Returns `null` when exactly one of `traceId`/`spanId` is present, or when
/// both are present but malformed or the all-zero sentinel — see
/// [SpanContext.isValid].
LogRecord? _decodeLogRecord(Map<String, Object?> json) {
  final traceId = json['traceId'] as String?;
  final spanId = json['spanId'] as String?;
  if (traceId != null || spanId != null) {
    if (traceId == null || spanId == null) return null;
    if (!SpanContext(traceId: traceId, spanId: spanId).isValid) return null;
  }
  return LogRecord(
    body: json['body']! as String,
    severity: LogSeverity.values.byName(json['severity']! as String),
    timestamp: _dateTimeFromUnixNano(json['timeUnixNano']! as String),
    attributes:
        (json['attributes'] as Map?)?.cast<String, Object?>() ?? const {},
    traceId: traceId,
    spanId: spanId,
  );
}

final RegExp _hexSpanId = RegExp(r'^[0-9a-f]{16}$');

bool _isValidSpanId(String value) =>
    _hexSpanId.hasMatch(value) && value.codeUnits.any((unit) => unit != 0x30);

DateTime _dateTimeFromUnixNano(String unixNano) =>
    DateTime.fromMicrosecondsSinceEpoch(
      int.parse(unixNano) ~/ 1000,
      isUtc: true,
    );
