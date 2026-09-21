import 'log_record.dart';

/// Sits between [Logger.emit] and a [LogRecordExporter], deciding *when*
/// records get exported (immediately, batched on a timer, ...).
abstract class LogRecordProcessor {
  /// Called synchronously every time a [LogRecord] is emitted. Must not
  /// throw; any exporting work it kicks off should be awaited internally
  /// (e.g. tracked so [forceFlush] can wait on it) rather than awaited here.
  void onEmit(LogRecord record);

  /// Waits for any in-flight or buffered export work to complete.
  Future<void> forceFlush();

  /// Flushes and then releases the processor (and its exporter).
  Future<void> shutdown();
}
