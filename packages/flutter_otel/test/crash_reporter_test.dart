import 'dart:ui';

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

  test('logs a framework error with its message and stack trace', () {
    installCrashReporting(logger);
    final stackTrace = StackTrace.current;

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('user typed: hunter2'),
        stack: stackTrace,
      ),
    );

    final record = logger.records.single;
    expect(record.severity, LogSeverity.error);
    expect(record.body, 'Uncaught Flutter error');
    expect(record.attributes['exception.type'], 'StateError');
    expect(
      record.attributes['exception.message'],
      contains('user typed: hunter2'),
    );
    expect(record.attributes['exception.stacktrace'], stackTrace.toString());
  });

  test('logs an uncaught async error with its message and stack trace', () {
    installCrashReporting(logger);
    final stackTrace = StackTrace.current;

    final handled = PlatformDispatcher.instance.onError!(
      ArgumentError('bad input'),
      stackTrace,
    );

    final record = logger.records.single;
    expect(record.body, 'Uncaught async error');
    expect(record.attributes['exception.type'], 'ArgumentError');
    expect(record.attributes['exception.message'], contains('bad input'));
    expect(record.attributes['exception.stacktrace'], stackTrace.toString());
    expect(handled, isFalse, reason: 'no previous handler was installed');
  });

  test('attaches recent breadcrumbs to the crash record', () {
    final trail = BreadcrumbTrail();
    trail.record('auth.signed_in');
    trail.record('session.created', {'profile': 'work'});
    installCrashReporting(logger, breadcrumbs: trail);

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));

    final record = logger.records.single;
    expect(record.attributes['breadcrumbs'], [
      trail.recent[0].toString(),
      trail.recent[1].toString(),
    ]);
  });

  test('omits the breadcrumbs attribute when there are none', () {
    installCrashReporting(logger, breadcrumbs: BreadcrumbTrail());

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));

    expect(
        logger.records.single.attributes.containsKey('breadcrumbs'), isFalse);
  });

  test('still calls the previously installed handlers', () {
    var flutterCalled = false;
    var platformCalled = false;
    FlutterError.onError = (_) => flutterCalled = true;
    PlatformDispatcher.instance.onError = (_, __) {
      platformCalled = true;
      return true;
    };

    installCrashReporting(logger);
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));
    final handled = PlatformDispatcher.instance.onError!(
      StateError('x'),
      StackTrace.empty,
    );

    expect(flutterCalled, isTrue);
    expect(platformCalled, isTrue);
    expect(handled, isTrue, reason: 'keeps the previous handler verdict');
  });

  test('a failing logger never swallows the error', () {
    var flutterCalled = false;
    FlutterError.onError = (_) => flutterCalled = true;

    installCrashReporting(ThrowingLogger());
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));

    expect(flutterCalled, isTrue);
  });
}
