import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_otel/flutter_otel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_logger.dart';

void main() {
  late RecordingLogger logger;
  late FlutterExceptionHandler? originalFlutterHandler;
  late ErrorCallback? originalPlatformHandler;
  late List<Object> flutterErrorsSeenByPrevious;
  late List<Object> platformErrorsSeenByPrevious;

  setUp(() {
    logger = RecordingLogger();
    originalFlutterHandler = FlutterError.onError;
    originalPlatformHandler = PlatformDispatcher.instance.onError;
    flutterErrorsSeenByPrevious = [];
    platformErrorsSeenByPrevious = [];
    FlutterError.onError =
        (details) => flutterErrorsSeenByPrevious.add(details.exception);
    PlatformDispatcher.instance.onError = (error, stack) {
      platformErrorsSeenByPrevious.add(error);
      return true;
    };
  });

  tearDown(() {
    FlutterError.onError = originalFlutterHandler;
    PlatformDispatcher.instance.onError = originalPlatformHandler;
  });

  test(
    'logs a framework error by type only and calls the previous handler',
    () {
      installUncaughtErrorLogging(logger);

      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('user typed: hunter2')),
      );

      final record = logger.records.single;
      expect(record.severity, LogSeverity.error);
      expect(record.body, 'Uncaught Flutter error');
      expect(record.attributes, {'exception.type': 'StateError'});
      expect(flutterErrorsSeenByPrevious, hasLength(1));
    },
  );

  test('logs an uncaught async error by type only', () {
    installUncaughtErrorLogging(logger);

    final handled = PlatformDispatcher.instance.onError!(
      ArgumentError('https://secret.example.org/?token=abc'),
      StackTrace.current,
    );

    final record = logger.records.single;
    expect(record.severity, LogSeverity.error);
    expect(record.body, 'Uncaught async error');
    expect(record.attributes, {'exception.type': 'ArgumentError'});
    expect(handled, isTrue, reason: 'keeps the previous handler verdict');
    expect(platformErrorsSeenByPrevious, hasLength(1));
  });

  test('leaves an error unhandled when there was no previous handler', () {
    PlatformDispatcher.instance.onError = null;
    installUncaughtErrorLogging(logger);

    final handled = PlatformDispatcher.instance.onError!(
      StateError('x'),
      StackTrace.current,
    );

    expect(handled, isFalse);
    expect(logger.records, hasLength(1));
  });

  test('a failing logger never swallows the error', () {
    installUncaughtErrorLogging(ThrowingLogger());

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));

    expect(flutterErrorsSeenByPrevious, hasLength(1));
  });
}
