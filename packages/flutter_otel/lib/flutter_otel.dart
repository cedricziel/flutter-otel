/// flutter_otel: an OpenTelemetry SDK for Flutter apps.
///
/// This umbrella package re-exports [flutter_otel_api], [flutter_otel_sdk],
/// and [flutter_otel_exporter_otlp_http] so a single import gives you the
/// full public API:
///
/// ```dart
/// import 'package:flutter_otel/flutter_otel.dart';
/// ```
///
/// See the package README for a usage example.
library;

export 'package:flutter_otel_api/flutter_otel_api.dart';
export 'package:flutter_otel_exporter_otlp_http/flutter_otel_exporter_otlp_http.dart';
export 'package:flutter_otel_sdk/flutter_otel_sdk.dart';
