import 'dart:convert';
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

  StackTrace deepStack(int frames) => StackTrace.fromString(
        [
          for (var i = 0; i < frames; i++)
            '#$i      _RenderObjectSemantics._buildSemantics '
                '(package:flutter/src/rendering/object.dart:6227)',
        ].join('\n'),
      );

  test('trims a long stack trace to whole frames within the byte limit', () {
    installCrashReporting(logger, maxValueBytes: 1000);
    final stack = deepStack(200);

    FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('x'), stack: stack),
    );

    final trimmed =
        logger.records.single.attributes['exception.stacktrace'] as String;
    final lines = trimmed.split('\n');
    expect(utf8.encode(trimmed).length, lessThanOrEqualTo(1000));
    expect(lines.first, stack.toString().split('\n').first);
    expect(lines.last, '... ${200 - (lines.length - 1)} more frames');
    expect(
      stack.toString(),
      startsWith(lines.take(lines.length - 1).join('\n')),
      reason: 'keeps the top frames, cut at a frame boundary',
    );
  });

  test('keeps the stack trace of an async error within the limit too', () {
    installCrashReporting(logger, maxValueBytes: 1000);

    PlatformDispatcher.instance.onError!(StateError('x'), deepStack(200));

    final trimmed =
        logger.records.single.attributes['exception.stacktrace'] as String;
    expect(utf8.encode(trimmed).length, lessThanOrEqualTo(1000));
  });

  test('trims a long exception message within the byte limit', () {
    installCrashReporting(logger, maxValueBytes: 100);

    FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('ä' * 500)),
    );

    final message =
        logger.records.single.attributes['exception.message'] as String;
    expect(utf8.encode(message).length, lessThanOrEqualTo(100));
    expect(message, startsWith('Bad state: ä'));
  });

  test('leaves the stack trace out when Flutter reports none', () {
    installCrashReporting(logger);

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));

    expect(
      logger.records.single.attributes.containsKey('exception.stacktrace'),
      isFalse,
    );
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

  group('breadcrumb size', () {
    // What SignalDB measures for an array attribute: the protobuf encoding
    // of the array, so every element costs its bytes plus framing.
    int varint(int value) => value < 0x80 ? 1 : (value < 0x4000 ? 2 : 3);
    int encodedLength(List<String> values) => values.fold(0, (sum, value) {
          final string =
              1 + varint(utf8.encode(value).length) + utf8.encode(value).length;
          return sum + 1 + varint(string) + string;
        });

    List<String> reportCrumbs(BreadcrumbTrail trail, {int? maxValueBytes}) {
      installCrashReporting(
        logger,
        breadcrumbs: trail,
        maxValueBytes: maxValueBytes ?? 4096,
      );
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));
      return (logger.records.single.attributes['breadcrumbs'] as List)
          .cast<String>();
    }

    test(
      'keeps the newest breadcrumbs that fit and says how many it dropped',
      () {
        final trail = BreadcrumbTrail(capacity: 40);
        for (var i = 0; i < 40; i++) {
          trail.record('event.$i', {'detail': 'x' * 100});
        }

        final crumbs = reportCrumbs(trail, maxValueBytes: 1000);

        expect(encodedLength(crumbs), lessThanOrEqualTo(1000));
        final dropped = 40 - (crumbs.length - 1);
        expect(dropped, greaterThan(0));
        expect(crumbs.first, '... $dropped older breadcrumbs dropped');
        expect(crumbs.skip(1), [
          for (final b in trail.recent.skip(dropped)) b.toString(),
        ]);
      },
    );

    test('fills the budget before dropping anything', () {
      final trail = BreadcrumbTrail(capacity: 40);
      for (var i = 0; i < 40; i++) {
        trail.record('event.$i', {'detail': 'x' * 100});
      }

      final crumbs = reportCrumbs(trail, maxValueBytes: 1000);

      final next = trail.recent[40 - (crumbs.length - 1) - 1].toString();
      expect(
        encodedLength([...crumbs, next]),
        greaterThan(1000),
        reason: 'one more breadcrumb would not have fit',
      );
    });

    test('adds no marker when every breadcrumb fits', () {
      final trail = BreadcrumbTrail();
      trail.record('a');
      trail.record('b');

      expect(reportCrumbs(trail), [
        trail.recent[0].toString(),
        trail.recent[1].toString(),
      ]);
    });

    test('keeps a full trail of 40 breadcrumbs within the default limit', () {
      final trail = BreadcrumbTrail(capacity: 40);
      for (var i = 0; i < 40; i++) {
        trail.record('chat.reply_finished', {
          'thread': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
          'chars': i * 1000,
        });
      }

      expect(encodedLength(reportCrumbs(trail)), lessThanOrEqualTo(4096));
    });

    test('cuts a single breadcrumb that is longer than the budget', () {
      final trail = BreadcrumbTrail();
      trail.record('old');
      trail.record('huge', {'payload': 'ä' * 5000});

      final crumbs = reportCrumbs(trail, maxValueBytes: 500);

      expect(encodedLength(crumbs), lessThanOrEqualTo(500));
      expect(crumbs.first, '... 1 older breadcrumbs dropped');
      expect(crumbs.last, contains('huge'));
      expect(crumbs.last, endsWith('…'));
    });
  });

  test('omits the breadcrumbs attribute when there are none', () {
    installCrashReporting(logger, breadcrumbs: BreadcrumbTrail());

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));

    expect(
      logger.records.single.attributes.containsKey('breadcrumbs'),
      isFalse,
    );
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
