import 'dart:convert';

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
///
/// The message and stack trace are each kept within [maxValueBytes] of
/// UTF-8, because collectors drop or cut attribute values above a size
/// limit (SignalDB drops any value over 4096 bytes by default, which loses
/// the whole stack trace of a deep widget tree). A stack trace is cut after
/// its last whole frame that fits, and ends with a line saying how many
/// frames were left out.
void installCrashReporting(
  Logger logger, {
  BreadcrumbTrail? breadcrumbs,
  int maxValueBytes = 4096,
}) {
  void log(String body, Object error, StackTrace? stackTrace) {
    try {
      logger.emit(
        LogRecord(
          body: body,
          severity: LogSeverity.error,
          attributes: {
            'exception.type': error.runtimeType.toString(),
            'exception.message': _trimText(error.toString(), maxValueBytes),
            if (stackTrace != null)
              'exception.stacktrace':
                  _trimStackTrace(stackTrace.toString(), maxValueBytes),
            ...?_breadcrumbAttributes(breadcrumbs),
          },
        ),
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

int _byteLength(String text) => utf8.encode(text).length;

String _trimText(String text, int maxBytes) {
  if (_byteLength(text) <= maxBytes) return text;
  const ellipsis = '…';
  final budget = maxBytes - _byteLength(ellipsis);
  final kept = StringBuffer();
  var used = 0;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    used += _byteLength(char);
    if (used > budget) break;
    kept.write(char);
  }
  return '$kept$ellipsis';
}

String _trimStackTrace(String stack, int maxBytes) {
  if (_byteLength(stack) <= maxBytes) return stack;
  final frames = stack.trimRight().split('\n');
  // Reserve room for the longest possible omission line.
  final budget = maxBytes - _byteLength('\n${_omitted(frames.length)}');
  final kept = <String>[];
  var used = 0;
  for (final frame in frames) {
    final cost = _byteLength(frame) + (kept.isEmpty ? 0 : 1);
    if (used + cost > budget) break;
    kept.add(frame);
    used += cost;
  }
  return [...kept, _omitted(frames.length - kept.length)].join('\n');
}

String _omitted(int frames) => '... $frames more frames';

Map<String, Object?>? _breadcrumbAttributes(BreadcrumbTrail? breadcrumbs) {
  if (breadcrumbs == null || breadcrumbs.recent.isEmpty) return null;
  return {
    'breadcrumbs': [for (final b in breadcrumbs.recent) b.toString()],
  };
}
