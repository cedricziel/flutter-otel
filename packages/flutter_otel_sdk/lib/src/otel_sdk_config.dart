import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:http/http.dart' as http;

/// Configuration for [OTelSdk.initialize].
class OTelSdkConfig {
  OTelSdkConfig({
    required this.resource,
    this.enabled = true,
    this.otlpEndpoint,
    this.otlpLogsEndpoint,
    this.otlpHeaders = const {},
    this.sessionTrackingEnabled = true,
    this.sessionTimeout = const Duration(minutes: 30),
    this.scheduledDelay = const Duration(seconds: 5),
    this.maxExportBatchSize = 512,
    this.maxQueueSize = 2048,
    this.httpClient,
    this.logExporter,
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
  /// The logs exporter resolves `/v1/logs` against it. Ignored if
  /// [otlpLogsEndpoint] or [logExporter] is set.
  final Uri? otlpEndpoint;

  /// Explicit logs endpoint override (mirrors
  /// `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT`), used verbatim when set.
  final Uri? otlpLogsEndpoint;

  /// Extra HTTP headers sent with every OTLP export request (mirrors
  /// `OTEL_EXPORTER_OTLP_HEADERS`).
  final Map<String, String> otlpHeaders;

  /// Whether to track a rolling session ID and merge it onto every log
  /// record as `session.id`.
  final bool sessionTrackingEnabled;

  /// How long the app can be idle before [DefaultSessionManager] starts a
  /// new session on the next activity.
  final Duration sessionTimeout;

  /// How often [BatchLogRecordProcessor] flushes on its periodic timer.
  final Duration scheduledDelay;

  /// The maximum number of records exported in a single batch.
  final int maxExportBatchSize;

  /// The maximum number of records buffered before older ones are dropped.
  final int maxQueueSize;

  /// The HTTP client used by the OTLP exporter. If omitted, the SDK
  /// constructs (and owns/closes) a default `http.Client()`. Ignored when
  /// [logExporter] is set.
  final http.Client? httpClient;

  /// Overrides the exporter entirely (e.g. for tests or a custom sink),
  /// bypassing [otlpEndpoint]/[otlpLogsEndpoint] resolution.
  final LogRecordExporter? logExporter;
}
