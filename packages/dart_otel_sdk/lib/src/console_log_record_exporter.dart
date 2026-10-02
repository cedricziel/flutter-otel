import 'package:dart_otel_api/dart_otel_api.dart';

const String _stackTraceAttribute = 'exception.stacktrace';

/// A [LogRecordExporter] that prints each record as one human-readable
/// line, for local development.
///
/// A line looks like `[WARN] scope.name: message {key: value}`; the
/// attribute map is left out when there are no attributes. A record that
/// carries an `exception.stacktrace` attribute prints it on the lines that
/// follow instead of inside the map.
class ConsoleLogRecordExporter implements LogRecordExporter {
  /// Creates an exporter that hands each formatted line to [printer].
  ///
  /// Records below [minSeverity] are dropped.
  ConsoleLogRecordExporter({
    void Function(String line) printer = print,
    this.minSeverity = LogSeverity.trace,
  }) : _printer = printer;

  final void Function(String line) _printer;

  /// The lowest severity that is printed.
  final LogSeverity minSeverity;

  @override
  Future<ExportResult> export(
    List<LogRecord> records,
    OTelResource resource,
  ) async {
    try {
      for (final record in records) {
        if (record.severity.index < minSeverity.index) continue;
        _printer(_format(record));
      }
      return const ExportResult.success();
    } catch (e) {
      return ExportResult.failure(e);
    }
  }

  String _format(LogRecord record) {
    final attributes = {...record.attributes};
    final stackTrace = attributes.remove(_stackTraceAttribute);
    final buffer = StringBuffer()
      ..write('[${record.severity.severityText}] ')
      ..write('${record.scopeName}: ${record.body}');
    if (attributes.isNotEmpty) {
      buffer.write(' $attributes');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    return buffer.toString();
  }

  @override
  Future<void> shutdown() async {}
}
