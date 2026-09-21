import 'package:dart_otel_api/dart_otel_api.dart';

class RecordingLogger extends Logger {
  final List<LogRecord> records = [];

  @override
  void emit(LogRecord record) => records.add(record);
}

class ThrowingLogger extends Logger {
  @override
  void emit(LogRecord record) => throw StateError('logger broke');
}
