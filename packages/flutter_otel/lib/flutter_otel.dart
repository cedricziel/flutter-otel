/// flutter_otel: an OpenTelemetry SDK for Flutter apps.
///
/// This umbrella package re-exports [dart_otel_api], [dart_otel_sdk],
/// and [dart_otel_exporter_otlp_http] so a single import gives you the
/// full public API:
///
/// ```dart
/// import 'package:flutter_otel/flutter_otel.dart';
/// ```
///
/// See the package README for a usage example.
library;

export 'package:dart_otel_api/dart_otel_api.dart';
export 'package:dart_otel_exporter_otlp_http/dart_otel_exporter_otlp_http.dart';
export 'package:dart_otel_sdk/dart_otel_sdk.dart';

export 'src/app_event_logger.dart';
export 'src/breadcrumb_trail.dart';
export 'src/crash_reporter.dart';
export 'src/default_session_manager.dart';
export 'src/otel_sdk.dart';
export 'src/uncaught_error_logging.dart';
