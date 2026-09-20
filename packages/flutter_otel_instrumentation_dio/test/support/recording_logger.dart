import 'package:flutter_otel_api/flutter_otel_api.dart';

class RecordingLogger extends Logger {
  final List<LogRecord> records = [];

  @override
  void emit(LogRecord record) => records.add(record);
}

class ThrowingLogger extends Logger {
  @override
  void emit(LogRecord record) => throw StateError('logger broke');
}
