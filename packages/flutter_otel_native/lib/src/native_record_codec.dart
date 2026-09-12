import 'dart:convert';

import 'package:flutter_otel_api/flutter_otel_api.dart';

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
    return switch (json['kind']) {
      'span' => NativeSpanRecord(_decodeSpanData(json)),
      'log' => NativeLogRecord(_decodeLogRecord(json)),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

SpanData _decodeSpanData(Map<String, Object?> json) {
  final eventsJson = (json['events'] as List?) ?? const [];
  return SpanData(
    name: json['name']! as String,
    spanContext: SpanContext(
      traceId: json['traceId']! as String,
      spanId: json['spanId']! as String,
    ),
    parentSpanId: json['parentSpanId'] as String?,
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

LogRecord _decodeLogRecord(Map<String, Object?> json) => LogRecord(
      body: json['body']! as String,
      severity: LogSeverity.values.byName(json['severity']! as String),
      timestamp: _dateTimeFromUnixNano(json['timeUnixNano']! as String),
      attributes:
          (json['attributes'] as Map?)?.cast<String, Object?>() ?? const {},
      traceId: json['traceId'] as String?,
      spanId: json['spanId'] as String?,
    );

DateTime _dateTimeFromUnixNano(String unixNano) =>
    DateTime.fromMicrosecondsSinceEpoch(
      int.parse(unixNano) ~/ 1000,
      isUtc: true,
    );
