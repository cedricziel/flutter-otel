import 'package:flutter/foundation.dart';
import 'package:dart_otel_api/dart_otel_api.dart';

import 'safely.dart';

/// Logs uncaught framework and async errors through [logger], then defers to
/// the handlers that were installed before.
///
/// Only the error type is recorded. Messages and stack traces can carry user
/// input, so they stay on the device.
void installUncaughtErrorLogging(Logger logger) {
  void log(String body, Object error) {
    safely(
      () => logger.emit(
        LogRecord(
          body: body,
          severity: LogSeverity.error,
          attributes: {'exception.type': error.runtimeType.toString()},
        ),
      ),
    );
  }

  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    log('Uncaught Flutter error', details.exception);
    previousFlutterHandler?.call(details);
  };

  final previousPlatformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    log('Uncaught async error', error);
    return previousPlatformHandler?.call(error, stack) ?? false;
  };
}
