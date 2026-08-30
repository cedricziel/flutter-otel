import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:flutter_otel_exporter_otlp_http/flutter_otel_exporter_otlp_http.dart';
import 'package:http/http.dart' as http;

import 'batch_log_record_processor.dart';
import 'default_session_manager.dart';
import 'otel_sdk_config.dart';
import 'sdk_logger_provider.dart';

/// Top-level facade for flutter_otel: owns the singleton SDK instance, the
/// [LoggerProvider] pipeline, and (optionally) a [SessionManager].
///
/// Traces and metrics are not implemented yet; [loggerProvider] is the only
/// signal surfaced today, but the shape (a provider + processor/exporter
/// pipeline keyed off a shared [OTelResource]) is designed so `tracerProvider`
/// and `meterProvider` can be added later without reshaping this class.
class OTelSdk {
  OTelSdk._({
    required this.loggerProvider,
    required this.sessionManager,
    required http.Client? ownedHttpClient,
  }) : _ownedHttpClient = ownedHttpClient;

  /// Owns [Logger] creation and the log processing/export pipeline.
  final LoggerProvider loggerProvider;

  /// Tracks the current session, or `null` when
  /// [OTelSdkConfig.sessionTrackingEnabled] was `false`.
  final SessionManager? sessionManager;

  final http.Client? _ownedHttpClient;

  static OTelSdk? _instance;

  /// Initializes the SDK from [config] and stores it as [instance].
  /// Calling this again replaces the previous instance without shutting it
  /// down first — call [reset] (or `instance.shutdown()`) beforehand if you
  /// need a clean teardown, which is what tests should do between cases.
  static Future<OTelSdk> initialize(OTelSdkConfig config) async {
    http.Client? ownedHttpClient;
    final exporter = _resolveExporter(config, onOwnedClient: (client) {
      ownedHttpClient = client;
    });

    final processor = BatchLogRecordProcessor(
      exporter,
      config.resource,
      maxQueueSize: config.maxQueueSize,
      maxExportBatchSize: config.maxExportBatchSize,
      scheduledDelay: config.scheduledDelay,
    );

    SessionManager? sessionManager;
    if (config.sessionTrackingEnabled) {
      sessionManager =
          DefaultSessionManager(idleTimeout: config.sessionTimeout);
    }

    final provider = SdkLoggerProvider(
      resource: config.resource,
      processor: processor,
      sessionManager: sessionManager,
    );

    final sdk = OTelSdk._(
      loggerProvider: provider,
      sessionManager: sessionManager,
      ownedHttpClient: ownedHttpClient,
    );
    _instance = sdk;
    return sdk;
  }

  static LogRecordExporter _resolveExporter(
    OTelSdkConfig config, {
    required void Function(http.Client) onOwnedClient,
  }) {
    if (!config.enabled) {
      return const NoopLogRecordExporter();
    }
    final override = config.logExporter;
    if (override != null) {
      return override;
    }
    final endpoint = OtlpHttpLogExporter.resolveLogsEndpoint(
      baseEndpoint: config.otlpEndpoint,
      logsEndpoint: config.otlpLogsEndpoint,
    );
    if (endpoint == null) {
      return const NoopLogRecordExporter();
    }
    final client = config.httpClient;
    if (client != null) {
      return OtlpHttpLogExporter(
        endpoint: endpoint,
        httpClient: client,
        headers: config.otlpHeaders,
      );
    }
    final ownedClient = http.Client();
    onOwnedClient(ownedClient);
    return OtlpHttpLogExporter(
      endpoint: endpoint,
      httpClient: ownedClient,
      headers: config.otlpHeaders,
      ownsClient: true,
    );
  }

  /// The current SDK instance. Throws [StateError] if [initialize] has not
  /// been called (or has been [reset]).
  static OTelSdk get instance {
    final current = _instance;
    if (current == null) {
      throw StateError(
        'OTelSdk has not been initialized. Call OTelSdk.initialize() first.',
      );
    }
    return current;
  }

  /// The current SDK instance, or `null` if not initialized.
  static OTelSdk? get maybeInstance => _instance;

  /// Shuts down the current instance (if any) and clears the singleton.
  /// Intended for use between test cases.
  static Future<void> reset() async {
    final current = _instance;
    _instance = null;
    if (current != null) {
      await current.shutdown();
    }
  }

  /// Convenience passthrough to `loggerProvider.getLogger(...)`.
  Logger getLogger({String name = 'flutter_otel', String? version}) =>
      loggerProvider.getLogger(name: name, version: version);

  /// Flushes the log pipeline (and, once implemented, trace/metric
  /// pipelines).
  Future<void> forceFlush() => loggerProvider.forceFlush();

  /// Flushes and releases every resource owned by this SDK instance: the
  /// log processor/exporter, any default-constructed HTTP client, and the
  /// session manager's lifecycle observer.
  Future<void> shutdown() async {
    await loggerProvider.forceFlush();
    await loggerProvider.shutdown();
    final manager = sessionManager;
    if (manager is DefaultSessionManager) {
      manager.dispose();
    }
    _ownedHttpClient?.close();
  }
}
