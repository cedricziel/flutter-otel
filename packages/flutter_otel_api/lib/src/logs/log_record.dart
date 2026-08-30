import 'log_severity.dart';

/// The default instrumentation scope name stamped onto a [LogRecord] when
/// no logger name is known yet. [LoggerProvider] implementations override
/// this with the name/version the caller passed to `getLogger()`.
const String defaultInstrumentationScopeName = 'flutter_otel';

/// A single log entry, independent of how it will be processed or exported.
///
/// Instances are immutable; [withAttributes] and [withScope] return copies
/// so processors/loggers can enrich a record (e.g. stamping `session.id` or
/// the emitting logger's instrumentation scope) without mutating the
/// caller's original record.
class LogRecord {
  LogRecord({
    required this.body,
    this.severity = LogSeverity.info,
    DateTime? timestamp,
    DateTime? observedTimestamp,
    Map<String, Object?> attributes = const {},
    this.traceId,
    this.spanId,
    this.scopeName = defaultInstrumentationScopeName,
    this.scopeVersion,
  })  : timestamp = timestamp ?? DateTime.now(),
        observedTimestamp = observedTimestamp ?? timestamp ?? DateTime.now(),
        attributes = Map.unmodifiable(attributes);

  /// The human-readable log message.
  final String body;

  /// The severity of this record.
  final LogSeverity severity;

  /// When the event described by this record occurred. Defaults to
  /// `DateTime.now()` at construction time.
  final DateTime timestamp;

  /// When this record was observed/collected. Defaults to [timestamp].
  final DateTime observedTimestamp;

  /// Structured attributes attached to this record. Read-only.
  final Map<String, Object?> attributes;

  /// Hex-encoded trace ID for future trace correlation, if this log was
  /// emitted within a traced operation.
  final String? traceId;

  /// Hex-encoded span ID for future trace correlation, if this log was
  /// emitted within a traced operation.
  final String? spanId;

  /// The name of the instrumentation scope (logger) that emitted this
  /// record.
  final String scopeName;

  /// The version of the instrumentation scope (logger) that emitted this
  /// record, if any.
  final String? scopeVersion;

  /// Returns a copy of this record with [extra] merged under its existing
  /// attributes. Existing attribute keys win on conflict, so callers can
  /// always override an auto-injected attribute (e.g. `session.id`) by
  /// setting it explicitly when emitting.
  LogRecord withAttributes(Map<String, Object?> extra) => LogRecord(
        body: body,
        severity: severity,
        timestamp: timestamp,
        observedTimestamp: observedTimestamp,
        attributes: {...extra, ...attributes},
        traceId: traceId,
        spanId: spanId,
        scopeName: scopeName,
        scopeVersion: scopeVersion,
      );

  /// Returns a copy of this record with [traceId]/[spanId] filled in for
  /// whichever of the two isn't already set. An explicit value the caller
  /// passed when constructing this record always wins — this only fills
  /// gaps, e.g. for automatic trace-to-log correlation when a log is
  /// emitted while a span is active.
  LogRecord withTraceCorrelation(String traceId, String spanId) => LogRecord(
        body: body,
        severity: severity,
        timestamp: timestamp,
        observedTimestamp: observedTimestamp,
        attributes: attributes,
        traceId: this.traceId ?? traceId,
        spanId: this.spanId ?? spanId,
        scopeName: scopeName,
        scopeVersion: scopeVersion,
      );

  /// Returns a copy of this record stamped with the given instrumentation
  /// scope name/version.
  LogRecord withScope(String name, String? version) => LogRecord(
        body: body,
        severity: severity,
        timestamp: timestamp,
        observedTimestamp: observedTimestamp,
        attributes: attributes,
        traceId: traceId,
        spanId: spanId,
        scopeName: name,
        scopeVersion: version,
      );

  @override
  String toString() =>
      'LogRecord(severity: $severity, body: $body, attributes: $attributes)';
}
