/// The outcome of a single export attempt made by any signal's exporter
/// (logs today; traces/metrics will reuse this same type later).
///
/// Exporters must never throw out of their `export()` method — network or
/// encoding failures are reported back as a failed [ExportResult] instead,
/// so that callers (processors) can decide how to react (typically: log via
/// `debugPrint` and move on) without crashing the host application.
class ExportResult {
  const ExportResult._(this.success, this.error);

  /// The export completed successfully (e.g. the collector responded 2xx).
  const ExportResult.success() : this._(true, null);

  /// The export failed. [error] carries whatever diagnostic is available:
  /// a status code and body, a caught exception, or a plain message.
  const ExportResult.failure([Object? error]) : this._(false, error);

  /// Whether the export succeeded.
  final bool success;

  /// Diagnostic information about the failure, or `null` on success.
  final Object? error;

  @override
  String toString() =>
      success ? 'ExportResult.success()' : 'ExportResult.failure($error)';

  @override
  bool operator ==(Object other) =>
      other is ExportResult && other.success == success && other.error == error;

  @override
  int get hashCode => Object.hash(success, error);
}
