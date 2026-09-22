import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:flutter/foundation.dart';

import 'breadcrumb_trail.dart';

/// Logs uncaught Flutter and async errors through [logger] with their full
/// message and stack trace, then defers to the handlers that were installed
/// before.
///
/// Unlike [installUncaughtErrorLogging], which records only the exception
/// type because messages and stack traces can carry user input bound for an
/// arbitrary OTLP endpoint, this is for apps exporting to their own
/// collector that want Sentry-like crash detail. When [breadcrumbs] is
/// given, its recent entries are attached to the crash record under a
/// `breadcrumbs` attribute.
void installCrashReporting(Logger logger, {BreadcrumbTrail? breadcrumbs}) {
  void log(String body, Object error, StackTrace? stackTrace) {
    try {
      logger.error(
        body,
        error: error,
        stackTrace: stackTrace,
        attributes: _breadcrumbAttributes(breadcrumbs),
      );
    } catch (_) {}
  }

  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    log('Uncaught Flutter error', details.exception, details.stack);
    previousFlutterHandler?.call(details);
  };

  final previousPlatformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    log('Uncaught async error', error, stack);
    return previousPlatformHandler?.call(error, stack) ?? false;
  };
}

Map<String, Object?>? _breadcrumbAttributes(BreadcrumbTrail? breadcrumbs) {
  if (breadcrumbs == null || breadcrumbs.recent.isEmpty) return null;
  return {
    'breadcrumbs': [for (final b in breadcrumbs.recent) b.toString()],
  };
}
