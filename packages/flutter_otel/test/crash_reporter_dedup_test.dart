import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_otel/flutter_otel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_logger.dart';

void main() {
  late RecordingLogger logger;
  late FlutterExceptionHandler? originalFlutterHandler;
  late ErrorCallback? originalPlatformHandler;

  setUp(() {
    logger = RecordingLogger();
    originalFlutterHandler = FlutterError.onError;
    originalPlatformHandler = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    FlutterError.onError = originalFlutterHandler;
    PlatformDispatcher.instance.onError = originalPlatformHandler;
  });

  StackTrace stackAt(String function) => StackTrace.fromString(
        '#0      $function (package:app/a.dart:1)\n'
        '#1      drawFrame (package:flutter/src/rendering/binding.dart:699)',
      );

  void reportFlutterError(
    String message, {
    StackTrace? stack,
  }) =>
      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError(message), stack: stack),
      );

  test('logs a repeating error once, then how often it repeated', () {
    fakeAsync((async) {
      installCrashReporting(logger);
      final stack = stackAt('paint');

      for (var i = 0; i < 1000; i++) {
        reportFlutterError('null check', stack: stack);
      }
      expect(logger.records, hasLength(1));
      expect(
        logger.records.single.attributes.containsKey('exception.repeat_count'),
        isFalse,
      );

      async.elapse(const Duration(minutes: 1));

      expect(logger.records, hasLength(2));
      final summary = logger.records.last;
      expect(summary.body, 'Uncaught Flutter error');
      expect(summary.attributes['exception.type'], 'StateError');
      expect(summary.attributes['exception.message'], contains('null check'));
      expect(summary.attributes['exception.stacktrace'], stack.toString());
      expect(summary.attributes['exception.repeat_count'], 999);
    });
  });

  test('counts the repeats again after each summary', () {
    fakeAsync((async) {
      installCrashReporting(logger);

      reportFlutterError('x');
      reportFlutterError('x');
      async.elapse(const Duration(minutes: 1));
      reportFlutterError('x');
      reportFlutterError('x');
      reportFlutterError('x');
      async.elapse(const Duration(minutes: 1));

      expect(
        [
          for (final r in logger.records) r.attributes['exception.repeat_count']
        ],
        [null, 1, 3],
      );
    });
  });

  test('sends no summary for an error that did not repeat', () {
    fakeAsync((async) {
      installCrashReporting(logger);

      reportFlutterError('x');
      async.elapse(const Duration(minutes: 5));

      expect(logger.records, hasLength(1));
    });
  });

  test('logs errors with another message or other top frames separately', () {
    fakeAsync((async) {
      installCrashReporting(logger);

      reportFlutterError('a', stack: stackAt('paint'));
      reportFlutterError('b', stack: stackAt('paint'));
      reportFlutterError('a', stack: stackAt('layout'));
      reportFlutterError('a', stack: stackAt('paint'));

      expect(logger.records, hasLength(3));
    });
  });

  test('deduplicates async errors too', () {
    fakeAsync((async) {
      installCrashReporting(logger);
      final stack = stackAt('load');

      for (var i = 0; i < 3; i++) {
        PlatformDispatcher.instance.onError!(StateError('x'), stack);
      }
      async.elapse(const Duration(minutes: 1));

      expect(logger.records, hasLength(2));
      expect(logger.records.last.body, 'Uncaught async error');
      expect(logger.records.last.attributes['exception.repeat_count'], 2);
    });
  });

  test('calls the previous handlers for every repeat', () {
    fakeAsync((async) {
      var flutterCalls = 0;
      var platformCalls = 0;
      FlutterError.onError = (_) => flutterCalls++;
      PlatformDispatcher.instance.onError = (_, __) {
        platformCalls++;
        return true;
      };
      installCrashReporting(logger);

      for (var i = 0; i < 5; i++) {
        reportFlutterError('x');
        PlatformDispatcher.instance.onError!(StateError('x'), StackTrace.empty);
      }

      expect(flutterCalls, 5);
      expect(platformCalls, 5);
    });
  });

  test('uses the configured summary interval', () {
    fakeAsync((async) {
      installCrashReporting(
        logger,
        deduplication: const CrashDeduplication(
          summaryInterval: Duration(seconds: 10),
        ),
      );

      reportFlutterError('x');
      reportFlutterError('x');
      async.elapse(const Duration(seconds: 9));
      expect(logger.records, hasLength(1));
      async.elapse(const Duration(seconds: 1));
      expect(logger.records, hasLength(2));
    });
  });

  test('forgets the least recently seen error beyond maxSignatures', () {
    fakeAsync((async) {
      installCrashReporting(
        logger,
        deduplication: const CrashDeduplication(maxSignatures: 2),
      );

      reportFlutterError('a');
      reportFlutterError('a');
      reportFlutterError('b');
      reportFlutterError('c'); // evicts 'a', reporting its pending repeat
      expect(
        [
          for (final r in logger.records)
            (
              r.attributes['exception.message'],
              r.attributes['exception.repeat_count'],
            ),
        ],
        [
          ('Bad state: a', null),
          ('Bad state: b', null),
          ('Bad state: a', 1),
          ('Bad state: c', null),
        ],
      );

      reportFlutterError('a'); // forgotten, so logged in full again
      expect(
          logger.records.last.attributes['exception.message'], 'Bad state: a');
      expect(
        logger.records.last.attributes.containsKey('exception.repeat_count'),
        isFalse,
      );
    });
  });

  test('logs every error when deduplication is off', () {
    fakeAsync((async) {
      installCrashReporting(logger, deduplication: null);

      for (var i = 0; i < 3; i++) {
        reportFlutterError('x');
      }

      expect(logger.records, hasLength(3));
    });
  });
}
