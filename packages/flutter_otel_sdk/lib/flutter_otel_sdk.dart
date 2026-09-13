/// Concrete OpenTelemetry SDK implementation: log and span processors, in
/// pure Dart with no Flutter dependency. The Flutter-specific facade
/// (`OTelSdk`) and session tracking (`DefaultSessionManager`) live in
/// `flutter_otel`, which builds on this package.
library;

export 'package:flutter_otel_api/flutter_otel_api.dart';

export 'src/batch_log_record_processor.dart';
export 'src/batch_span_processor.dart';
export 'src/otel_sdk_config.dart';
export 'src/sdk_logger_provider.dart';
export 'src/sdk_span.dart';
export 'src/sdk_tracer.dart';
export 'src/sdk_tracer_provider.dart';
export 'src/simple_log_record_processor.dart';
export 'src/simple_span_processor.dart';
