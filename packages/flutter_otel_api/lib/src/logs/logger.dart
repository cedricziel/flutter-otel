import 'log_record.dart';
import 'log_severity.dart';

/// Emits [LogRecord]s. Concrete implementations only need to provide
/// [emit]; the severity-specific convenience methods are implemented in
/// terms of it so every implementation (and every mock) gets them for
/// free while still only exposing one seam to fake in tests.
abstract class Logger {
  /// Emits a fully-constructed [LogRecord].
  void emit(LogRecord record);

  /// Emits a TRACE-severity record. Not part of the fixed public contract,
  /// but provided for symmetry with [LogSeverity.trace].
  void trace(String body, {Map<String, Object?>? attributes}) => emit(
        LogRecord(
          body: body,
          severity: LogSeverity.trace,
          attributes: attributes ?? const {},
        ),
      );

  /// Emits a DEBUG-severity record.
  void debug(String body, {Map<String, Object?>? attributes}) => emit(
        LogRecord(
          body: body,
          severity: LogSeverity.debug,
          attributes: attributes ?? const {},
        ),
      );

  /// Emits an INFO-severity record.
  void info(String body, {Map<String, Object?>? attributes}) => emit(
        LogRecord(
          body: body,
          severity: LogSeverity.info,
          attributes: attributes ?? const {},
        ),
      );

  /// Emits a WARN-severity record.
  void warn(String body, {Map<String, Object?>? attributes}) => emit(
        LogRecord(
          body: body,
          severity: LogSeverity.warn,
          attributes: attributes ?? const {},
        ),
      );

  /// Emits an ERROR-severity record. When [error] and/or [stackTrace] are
  /// given they are captured as `exception.*` attributes alongside any
  /// caller-supplied [attributes].
  void error(
    String body, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? attributes,
  }) =>
      emit(
        LogRecord(
          body: body,
          severity: LogSeverity.error,
          attributes: {
            if (error != null) 'exception.type': error.runtimeType.toString(),
            if (error != null) 'exception.message': error.toString(),
            if (stackTrace != null)
              'exception.stacktrace': stackTrace.toString(),
            ...?attributes,
          },
        ),
      );

  /// Emits a FATAL-severity record. Not part of the fixed public contract,
  /// but provided for symmetry with [LogSeverity.fatal].
  void fatal(String body, {Map<String, Object?>? attributes}) => emit(
        LogRecord(
          body: body,
          severity: LogSeverity.fatal,
          attributes: attributes ?? const {},
        ),
      );
}
