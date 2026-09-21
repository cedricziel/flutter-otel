import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:test/test.dart';

class _RecordingLogger extends Logger {
  final List<LogRecord> emitted = [];

  @override
  void emit(LogRecord record) => emitted.add(record);
}

void main() {
  group('Logger convenience methods', () {
    late _RecordingLogger logger;

    setUp(() {
      logger = _RecordingLogger();
    });

    test('debug emits a DEBUG record', () {
      logger.debug('debug message', attributes: {'k': 'v'});
      expect(logger.emitted, hasLength(1));
      expect(logger.emitted.single.severity, LogSeverity.debug);
      expect(logger.emitted.single.body, 'debug message');
      expect(logger.emitted.single.attributes, {'k': 'v'});
    });

    test('info emits an INFO record', () {
      logger.info('info message');
      expect(logger.emitted.single.severity, LogSeverity.info);
    });

    test('warn emits a WARN record', () {
      logger.warn('warn message');
      expect(logger.emitted.single.severity, LogSeverity.warn);
    });

    test('trace emits a TRACE record', () {
      logger.trace('trace message');
      expect(logger.emitted.single.severity, LogSeverity.trace);
    });

    test('fatal emits a FATAL record', () {
      logger.fatal('fatal message');
      expect(logger.emitted.single.severity, LogSeverity.fatal);
    });

    test('error emits an ERROR record with plain attributes', () {
      logger.error('error message', attributes: {'k': 'v'});
      final record = logger.emitted.single;
      expect(record.severity, LogSeverity.error);
      expect(record.attributes, {'k': 'v'});
    });

    test('error captures exception details when error/stackTrace given', () {
      final stackTrace = StackTrace.current;
      logger.error(
        'boom',
        error: ArgumentError('bad value'),
        stackTrace: stackTrace,
        attributes: {'extra': 1},
      );
      final record = logger.emitted.single;
      expect(record.severity, LogSeverity.error);
      expect(record.attributes['exception.type'], contains('ArgumentError'));
      expect(record.attributes['exception.message'], contains('bad value'));
      expect(record.attributes['exception.stacktrace'], stackTrace.toString());
      expect(record.attributes['extra'], 1);
    });
  });
}
