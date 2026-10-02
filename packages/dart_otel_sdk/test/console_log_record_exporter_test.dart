import 'package:dart_otel_sdk/dart_otel_sdk.dart';
import 'package:test/test.dart';

void main() {
  late List<String> lines;
  late OTelResource resource;

  setUp(() {
    lines = [];
    resource = OTelResource(serviceName: 'test');
  });

  ConsoleLogRecordExporter exporter({
    LogSeverity minSeverity = LogSeverity.trace,
  }) =>
      ConsoleLogRecordExporter(printer: lines.add, minSeverity: minSeverity);

  group('ConsoleLogRecordExporter', () {
    test('prints severity text, scope name and body', () async {
      final result = await exporter().export([
        LogRecord(
          body: 'Failed to load pools',
          severity: LogSeverity.warn,
          scopeName: 'truehub.pools',
        ),
      ], resource);

      expect(result.success, isTrue);
      expect(lines, ['[WARN] truehub.pools: Failed to load pools']);
    });

    test('appends attributes when present', () async {
      await exporter().export([
        LogRecord(
          body: 'Failed to load pools',
          severity: LogSeverity.warn,
          scopeName: 'truehub.pools',
          attributes: {'server.id': 'abc', 'retries': 2},
        ),
      ], resource);

      expect(lines, [
        '[WARN] truehub.pools: Failed to load pools '
            '{server.id: abc, retries: 2}',
      ]);
    });

    test('prints one line per record in order', () async {
      await exporter().export([
        LogRecord(body: 'one'),
        LogRecord(body: 'two'),
      ], resource);

      expect(lines, hasLength(2));
      expect(lines[0], endsWith('one'));
      expect(lines[1], endsWith('two'));
    });

    test('drops records below minSeverity', () async {
      await exporter(minSeverity: LogSeverity.warn).export([
        LogRecord(body: 'debug', severity: LogSeverity.debug),
        LogRecord(body: 'info', severity: LogSeverity.info),
        LogRecord(body: 'warn', severity: LogSeverity.warn),
        LogRecord(body: 'error', severity: LogSeverity.error),
      ], resource);

      expect(lines, hasLength(2));
      expect(lines[0], contains('warn'));
      expect(lines[1], contains('error'));
    });

    test('prints exception.stacktrace on the following lines', () async {
      await exporter().export([
        LogRecord(
          body: 'boom',
          severity: LogSeverity.error,
          scopeName: 'app',
          attributes: {'exception.stacktrace': '#0 main\n#1 run'},
        ),
      ], resource);

      expect(lines, ['[ERROR] app: boom\n#0 main\n#1 run']);
    });

    test('does not repeat the stack trace inside the attribute map', () async {
      await exporter().export([
        LogRecord(
          body: 'boom',
          attributes: {'exception.stacktrace': '#0 main', 'a': 1},
        ),
      ], resource);

      expect(lines, ['[INFO] flutter_otel: boom {a: 1}\n#0 main']);
    });

    test(
      'omits the attribute map when only a stack trace is attached',
      () async {
        await exporter().export([
          LogRecord(body: 'boom', attributes: {'exception.stacktrace': '#0 x'}),
        ], resource);

        expect(lines, ['[INFO] flutter_otel: boom\n#0 x']);
      },
    );

    test(
      'returns a failed result instead of throwing when the printer throws',
      () async {
        final throwing = ConsoleLogRecordExporter(
          printer: (_) => throw StateError('no stdout'),
        );

        final result = await throwing.export([LogRecord(body: 'x')], resource);

        expect(result.success, isFalse);
      },
    );

    test('shutdown completes', () async {
      await expectLater(exporter().shutdown(), completes);
    });
  });
}
