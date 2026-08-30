import 'span_data.dart';

/// Sits between [Span.end] and a [SpanExporter], deciding *when* finished
/// spans get exported (immediately, batched on a timer, ...).
///
/// Deliberately has no `onStart` hook in this first pass: it isn't needed
/// for batching/export, so the surface is kept to what's used.
abstract class SpanProcessor {
  /// Called synchronously every time a span ends. Must not throw; any
  /// exporting work it kicks off should be awaited internally (e.g.
  /// tracked so [forceFlush] can wait on it) rather than awaited here.
  void onEnd(SpanData span);

  /// Waits for any in-flight or buffered export work to complete.
  Future<void> forceFlush();

  /// Flushes and then releases the processor (and its exporter).
  Future<void> shutdown();
}
