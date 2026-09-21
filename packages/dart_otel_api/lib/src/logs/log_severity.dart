/// OpenTelemetry log severity, matching the spec's severity number ranges:
/// TRACE=1..4, DEBUG=5..8, INFO=9..12, WARN=13..16, ERROR=17..20, FATAL=21..24.
///
/// Each enum value maps to the first number in its range via
/// [LogSeverityNumber.severityNumber].
enum LogSeverity { trace, debug, info, warn, error, fatal }

/// Maps [LogSeverity] to the OTLP `severityNumber` / `severityText` fields.
extension LogSeverityNumber on LogSeverity {
  /// The first `severityNumber` in this severity's OTel range.
  int get severityNumber => switch (this) {
        LogSeverity.trace => 1,
        LogSeverity.debug => 5,
        LogSeverity.info => 9,
        LogSeverity.warn => 13,
        LogSeverity.error => 17,
        LogSeverity.fatal => 21,
      };

  /// The OTel `severityText` for this severity.
  String get severityText => switch (this) {
        LogSeverity.trace => 'TRACE',
        LogSeverity.debug => 'DEBUG',
        LogSeverity.info => 'INFO',
        LogSeverity.warn => 'WARN',
        LogSeverity.error => 'ERROR',
        LogSeverity.fatal => 'FATAL',
      };
}
