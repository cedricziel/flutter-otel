import 'log_record.dart';
import 'logger.dart';

/// Vends named [Logger] instances and owns the flush/shutdown lifecycle of
/// whatever pipeline sits behind them.
abstract class LoggerProvider {
  /// Returns a [Logger] for the given instrumentation scope. Implementations
  /// typically cache and return the same instance for a given
  /// name/version pair.
  Logger getLogger({String name = 'flutter_otel', String? version});

  /// Feeds an externally-produced [LogRecord] directly into the processor
  /// pipeline — e.g. one recorded natively before Dart ran.
  void ingestLogRecord(LogRecord record);

  /// Forces any buffered records to be exported now. Resolves once the
  /// attempt (successful or not) has completed.
  Future<void> forceFlush();

  /// Flushes and releases any resources (timers, HTTP clients) held by the
  /// underlying pipeline. After this resolves, loggers obtained from this
  /// provider should no longer be used.
  Future<void> shutdown();
}
