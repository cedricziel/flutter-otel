import 'dart:async';
import 'dart:convert';

import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:flutter/foundation.dart';

import 'breadcrumb_trail.dart';
import 'safely.dart';

/// How [installCrashReporting] collapses an error that keeps recurring,
/// such as one thrown on every frame.
///
/// The first occurrence of an error is logged in full. Later occurrences
/// with the same signature (exception type, message and top five stack
/// frames) are counted instead, and at most once
/// per [summaryInterval] the error is logged again with an
/// `exception.repeat_count` attribute: how many occurrences that record
/// stands for. Up to [maxSignatures] errors are tracked; the least recently
/// seen one beyond that is forgotten, after its pending count is logged.
class CrashDeduplication {
  const CrashDeduplication({
    this.summaryInterval = const Duration(minutes: 1),
    this.maxSignatures = 100,
  });

  final Duration summaryInterval;
  final int maxSignatures;
}

const _signatureFrames = 5;

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
/// An error that recurs is logged once and then summarized as
/// [deduplication] describes; pass `null` to log every occurrence. The
/// previous handlers see every occurrence either way.
///
/// The message and stack trace are each kept within [maxValueBytes] of
/// UTF-8, because collectors drop or cut attribute values above a size
/// limit (SignalDB drops any value over 4096 bytes by default, which loses
/// the whole stack trace of a deep widget tree). A stack trace is cut after
/// its last whole frame that fits, and ends with a line saying how many
/// frames were left out. The `breadcrumbs` array is kept within the same
/// limit, counted as the collector does (all elements together): the oldest
/// entries are left out first, and a line at the start says how many.
void installCrashReporting(
  Logger logger, {
  BreadcrumbTrail? breadcrumbs,
  CrashDeduplication? deduplication = const CrashDeduplication(),
  int maxValueBytes = 4096,
}) {
  final crashLog = _CrashLog(logger, breadcrumbs, deduplication, maxValueBytes);

  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    crashLog.report('Uncaught Flutter error', details.exception, details.stack);
    previousFlutterHandler?.call(details);
  };

  final previousPlatformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    crashLog.report('Uncaught async error', error, stack);
    return previousPlatformHandler?.call(error, stack) ?? false;
  };
}

typedef _Signature = (String body, String type, String message, String? frames);

String? _topFrames(String? stack) {
  if (stack == null) return null;
  var end = -1;
  for (var i = 0; i < _signatureFrames; i++) {
    end = stack.indexOf('\n', end + 1);
    if (end == -1) return stack;
  }
  return stack.substring(0, end);
}

class _SeenError {
  _SeenError(this.body, this.attributes);

  final String body;
  final Map<String, Object?> attributes;
  int repeats = 0;
}

class _CrashLog {
  _CrashLog(
    this.logger,
    this.breadcrumbs,
    this.deduplication,
    this.maxValueBytes,
  );

  final Logger logger;
  final BreadcrumbTrail? breadcrumbs;
  final CrashDeduplication? deduplication;
  final int maxValueBytes;

  /// Errors by signature, least recently seen first.
  final _seen = <_Signature, _SeenError>{};
  Timer? _summaryTimer;

  void report(String body, Object error, StackTrace? stackTrace) =>
      safely(() => _report(body, error, stackTrace));

  void _report(String body, Object error, StackTrace? stackTrace) {
    final type = error.runtimeType.toString();
    final message = error.toString();
    final stack = stackTrace?.toString();
    final deduplication = this.deduplication;
    if (deduplication == null) {
      return _emit(body, _attributes(type, message, stack));
    }

    // Looked up before anything is trimmed: an error repeating every frame
    // only pays for this.
    final signature = (body, type, message, _topFrames(stack));
    final seen = _seen.remove(signature);
    if (seen != null) {
      seen.repeats++;
      _seen[signature] = seen;
      _summaryTimer ??= Timer(
        deduplication.summaryInterval,
        () => safely(_summarizeAll),
      );
      return;
    }
    final attributes = _attributes(type, message, stack);
    _seen[signature] = _SeenError(body, attributes);
    if (_seen.length > deduplication.maxSignatures) {
      _summarize(_seen.remove(_seen.keys.first)!);
    }
    _emit(body, attributes);
  }

  Map<String, Object?> _attributes(
          String type, String message, String? stack) =>
      {
        'exception.type': type,
        'exception.message': _trimText(message, maxValueBytes),
        if (stack != null)
          'exception.stacktrace': _trimStackTrace(stack, maxValueBytes),
      };

  void _summarizeAll() {
    _summaryTimer = null;
    _seen.values.forEach(_summarize);
  }

  void _summarize(_SeenError seen) {
    if (seen.repeats == 0) return;
    _emit(seen.body, {
      ...seen.attributes,
      'exception.repeat_count': seen.repeats,
    });
    seen.repeats = 0;
  }

  void _emit(String body, Map<String, Object?> attributes) => logger.emit(
        LogRecord(
          body: body,
          severity: LogSeverity.error,
          attributes: {
            ...attributes,
            ...?_breadcrumbAttributes(breadcrumbs, maxValueBytes),
          },
        ),
      );
}

int _byteLength(String text) => utf8.encode(text).length;

String _trimText(String text, int maxBytes) {
  final bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) return text;
  const ellipsis = '…';
  var cut = maxBytes - utf8.encode(ellipsis).length;
  // Step back to the start of a character, past its continuation bytes.
  while (cut > 0 && bytes[cut] & 0xC0 == 0x80) {
    cut--;
  }
  return '${utf8.decode(bytes.sublist(0, cut))}$ellipsis';
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

Map<String, Object?>? _breadcrumbAttributes(
  BreadcrumbTrail? breadcrumbs,
  int maxBytes,
) {
  if (breadcrumbs == null || breadcrumbs.recent.isEmpty) return null;
  return {
    'breadcrumbs': _trimBreadcrumbs(
      [for (final b in breadcrumbs.recent) b.toString()],
      maxBytes,
    ),
  };
}

/// Keeps the newest of [crumbs] (oldest first) that fit [maxBytes] as an
/// attribute array, and starts the result with a line saying how many older
/// ones were left out.
///
/// A collector counts an array as a whole, so the limit covers every element
/// together with its protobuf framing, not each string alone.
List<String> _trimBreadcrumbs(List<String> crumbs, int maxBytes) {
  final costs = [for (final crumb in crumbs) _elementBytes(_byteLength(crumb))];
  if (costs.fold(0, (sum, cost) => sum + cost) <= maxBytes) return crumbs;
  // Reserve room for the longest possible omission line.
  final budget =
      maxBytes - _elementBytes(_byteLength(_olderDropped(crumbs.length)));
  final kept = <String>[];
  var used = 0;
  for (var i = crumbs.length - 1; i >= 0; i--) {
    if (used + costs[i] > budget) break;
    kept.add(crumbs[i]);
    used += costs[i];
  }
  if (kept.isEmpty) {
    // Even the newest one alone is too long.
    var textBytes = budget;
    while (textBytes > 0 && _elementBytes(textBytes) > budget) {
      textBytes--;
    }
    kept.add(_trimText(crumbs.last, textBytes));
  }
  return [_olderDropped(crumbs.length - kept.length), ...kept.reversed];
}

String _olderDropped(int count) => '... $count older breadcrumbs dropped';

/// What one string of [textBytes] adds to an array attribute, as SignalDB
/// counts it: a length-delimited `AnyValue` holding a length-delimited
/// string, each with a one byte tag and a varint length.
int _elementBytes(int textBytes) {
  final value = 1 + _varintLength(textBytes) + textBytes;
  return 1 + _varintLength(value) + value;
}

int _varintLength(int value) {
  var length = 1;
  for (var rest = value >> 7; rest > 0; rest >>= 7) {
    length++;
  }
  return length;
}
