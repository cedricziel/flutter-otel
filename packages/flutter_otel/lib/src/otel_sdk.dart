import 'package:flutter/widgets.dart';
import 'package:dart_otel_exporter_otlp_http/dart_otel_exporter_otlp_http.dart';
import 'package:dart_otel_sdk/dart_otel_sdk.dart';
import 'package:http/http.dart' as http;

import 'default_session_manager.dart';

/// Top-level facade for flutter_otel: owns the singleton SDK instance, the
/// [LoggerProvider] pipeline, the [TracerProvider] pipeline, and
/// (optionally) a [SessionManager].
///
/// Metrics are not implemented yet; [loggerProvider] and [tracerProvider]
/// are the signals surfaced today, but the shape (a provider +
/// processor/exporter pipeline keyed off a shared [OTelResource]) is
/// designed so `meterProvider` can be added later without reshaping this
/// class.
class OTelSdk {
  OTelSdk._({
    required this.loggerProvider,
    required this.tracerProvider,
    required this.sessionManager,
    required List<http.Client> ownedHttpClients,
  }) : _ownedHttpClients = ownedHttpClients;

  /// Owns [Logger] creation and the log processing/export pipeline.
  final LoggerProvider loggerProvider;

  /// Owns [Tracer] creation and the span processing/export pipeline.
  final TracerProvider tracerProvider;

  /// Tracks the current session, or `null` when
  /// [OTelSdkConfig.sessionTrackingEnabled] was `false`.
  final SessionManager? sessionManager;

  // A list rather than a single client: logs and traces each resolve their
  // own default-constructed client (when `config.httpClient` isn't given),
  // so up to two owned clients may need closing on shutdown.
  final List<http.Client> _ownedHttpClients;

  static OTelSdk? _instance;

  /// Initializes the SDK from [config] and stores it as [instance].
  /// Calling this again replaces the previous instance without shutting it
  /// down first — call [reset] (or `instance.shutdown()`) beforehand if you
  /// need a clean teardown, which is what tests should do between cases.
  static Future<OTelSdk> initialize(OTelSdkConfig config) async {
    final ownedHttpClients = <http.Client>[];
    void onOwnedClient(http.Client client) => ownedHttpClients.add(client);

    final logExporter = _resolveExporter(config, onOwnedClient: onOwnedClient);
    final logProcessor = BatchLogRecordProcessor(
      logExporter,
      config.resource,
      maxQueueSize: config.maxQueueSize,
      maxExportBatchSize: config.maxExportBatchSize,
      scheduledDelay: config.scheduledDelay,
    );

    final spanExporter = _resolveSpanExporter(
      config,
      onOwnedClient: onOwnedClient,
    );
    final spanProcessor = BatchSpanProcessor(
      spanExporter,
      config.resource,
      maxQueueSize: config.maxQueueSize,
      maxExportBatchSize: config.maxExportBatchSize,
      scheduledDelay: config.scheduledDelay,
    );

    SessionManager? sessionManager;
    if (config.sessionTrackingEnabled) {
      // DefaultSessionManager registers a WidgetsBindingObserver via
      // WidgetsBinding.instance, which throws if no binding has been
      // initialized yet. A consumer calling OTelSdk.initialize(...) as the
      // very first line of main() (before runApp/ensureInitialized) is
      // reasonable and common, so make sure a binding exists here.
      // ensureInitialized() is idempotent and safe to call multiple times,
      // even if the consumer already called it themselves.
      WidgetsFlutterBinding.ensureInitialized();
      sessionManager = DefaultSessionManager(
        idleTimeout: config.sessionTimeout,
      );
    }

    final loggerProvider = SdkLoggerProvider(
      resource: config.resource,
      processor: logProcessor,
      sessionManager: sessionManager,
    );
    final tracerProvider = SdkTracerProvider(processor: spanProcessor);

    final sdk = OTelSdk._(
      loggerProvider: loggerProvider,
      tracerProvider: tracerProvider,
      sessionManager: sessionManager,
      ownedHttpClients: ownedHttpClients,
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

  static SpanExporter _resolveSpanExporter(
    OTelSdkConfig config, {
    required void Function(http.Client) onOwnedClient,
  }) {
    if (!config.enabled) {
      return const NoopSpanExporter();
    }
    final override = config.spanExporter;
    if (override != null) {
      return override;
    }
    final endpoint = OtlpHttpSpanExporter.resolveTracesEndpoint(
      baseEndpoint: config.otlpEndpoint,
      tracesEndpoint: config.otlpTracesEndpoint,
    );
    if (endpoint == null) {
      return const NoopSpanExporter();
    }
    final client = config.httpClient;
    if (client != null) {
      return OtlpHttpSpanExporter(
        endpoint: endpoint,
        httpClient: client,
        headers: config.otlpHeaders,
      );
    }
    final ownedClient = http.Client();
    onOwnedClient(ownedClient);
    return OtlpHttpSpanExporter(
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

  /// Convenience passthrough to `tracerProvider.getTracer(...)`.
  Tracer getTracer({String name = 'flutter_otel', String? version}) =>
      tracerProvider.getTracer(name: name, version: version);

  /// Flushes the log and trace pipelines (and, once implemented, the metric
  /// pipeline).
  Future<void> forceFlush() async {
    await Future.wait([
      loggerProvider.forceFlush(),
      tracerProvider.forceFlush(),
    ]);
  }

  /// Flushes and releases every resource owned by this SDK instance: the
  /// log and span processors/exporters, any default-constructed HTTP
  /// client(s), and the session manager's lifecycle observer.
  Future<void> shutdown() async {
    await forceFlush();
    await Future.wait([loggerProvider.shutdown(), tracerProvider.shutdown()]);
    final manager = sessionManager;
    if (manager is DefaultSessionManager) {
      manager.dispose();
    }
    for (final client in _ownedHttpClients) {
      client.close();
    }
  }
}
