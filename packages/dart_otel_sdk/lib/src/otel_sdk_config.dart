import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:http/http.dart' as http;

/// Configuration for [OTelSdk.initialize].
class OTelSdkConfig {
  OTelSdkConfig({
    required this.resource,
    this.enabled = true,
    this.otlpEndpoint,
    this.otlpLogsEndpoint,
    this.otlpTracesEndpoint,
    this.otlpHeaders = const {},
    this.sessionTrackingEnabled = true,
    this.sessionTimeout = const Duration(minutes: 30),
    this.scheduledDelay = const Duration(seconds: 5),
    this.maxExportBatchSize = 512,
    this.maxQueueSize = 2048,
    this.httpClient,
    this.logExporter,
    this.spanExporter,
  }) {
    if (maxQueueSize <= 0) {
      throw ArgumentError.value(
        maxQueueSize,
        'maxQueueSize',
        'Must be greater than 0.',
      );
    }
    if (maxExportBatchSize <= 0) {
      throw ArgumentError.value(
        maxExportBatchSize,
        'maxExportBatchSize',
        'Must be greater than 0.',
      );
    }
    if (scheduledDelay <= Duration.zero) {
      throw ArgumentError.value(
        scheduledDelay,
        'scheduledDelay',
        'Must be greater than Duration.zero.',
      );
    }
  }

  /// Describes the app/service producing telemetry.
  final OTelResource resource;

  /// When `false`, the SDK wires up a no-op exporter: every logging call
  /// still works, but nothing is ever sent over the network.
  final bool enabled;

  /// General OTLP base endpoint (mirrors `OTEL_EXPORTER_OTLP_ENDPOINT`).
  /// The logs exporter resolves `/v1/logs` and the traces exporter resolves
  /// `/v1/traces` against it. Ignored per-signal when that signal's
  /// specific endpoint or exporter override is set.
  final Uri? otlpEndpoint;

  /// Explicit logs endpoint override (mirrors
  /// `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT`), used verbatim when set.
  final Uri? otlpLogsEndpoint;

  /// Explicit traces endpoint override (mirrors
  /// `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`), used verbatim when set.
  final Uri? otlpTracesEndpoint;

  /// Extra HTTP headers sent with every OTLP export request (mirrors
  /// `OTEL_EXPORTER_OTLP_HEADERS`).
  final Map<String, String> otlpHeaders;

  /// Whether to track a rolling session ID and merge it onto every log
  /// record as `session.id`.
  final bool sessionTrackingEnabled;

  /// How long the app can be idle before [DefaultSessionManager] starts a
  /// new session on the next activity.
  final Duration sessionTimeout;

  /// How often [BatchLogRecordProcessor]/[BatchSpanProcessor] flush on
  /// their periodic timer.
  ///
  /// Shared across both signals rather than duplicated as
  /// per-signal settings — a deliberate simplification for this pass; a
  /// later change could split logs/traces batch tuning if they ever need
  /// to diverge.
  final Duration scheduledDelay;

  /// The maximum number of records/spans exported in a single batch.
  /// Shared across both signals (see [scheduledDelay]).
  final int maxExportBatchSize;

  /// The maximum number of records/spans buffered before older ones are
  /// dropped. Shared across both signals (see [scheduledDelay]).
  final int maxQueueSize;

  /// The HTTP client used by the OTLP exporters. When set, this same client
  /// instance is passed to (and shared by) both the logs and traces
  /// exporters. When omitted, [OTelSdk.initialize] constructs and owns a
  /// separate default `http.Client()` for each exporter that needs one — one
  /// for logs, one for traces, not a single shared client — and closes each
  /// on shutdown. Ignored for a signal whose exporter is overridden
  /// ([logExporter]/[spanExporter]).
  final http.Client? httpClient;

  /// Overrides the log exporter entirely (e.g. for tests or a custom
  /// sink), bypassing [otlpEndpoint]/[otlpLogsEndpoint] resolution.
  final LogRecordExporter? logExporter;

  /// Overrides the span exporter entirely (e.g. for tests or a custom
  /// sink), bypassing [otlpEndpoint]/[otlpTracesEndpoint] resolution.
  final SpanExporter? spanExporter;
}
