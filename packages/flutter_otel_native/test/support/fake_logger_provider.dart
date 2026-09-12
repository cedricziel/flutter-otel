import 'package:flutter_otel_api/flutter_otel_api.dart';

/// A [LoggerProvider] test double that records every record passed to
/// [ingestLogRecord] instead of exporting it anywhere.
class FakeLoggerProvider implements LoggerProvider {
  final List<LogRecord> ingestedRecords = [];

  @override
  void ingestLogRecord(LogRecord record) => ingestedRecords.add(record);

  @override
  Logger getLogger({String name = 'flutter_otel', String? version}) =>
      throw UnimplementedError('not exercised by NativeTelemetryBridge');

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
