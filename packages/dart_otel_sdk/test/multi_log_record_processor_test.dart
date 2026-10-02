import 'package:dart_otel_sdk/dart_otel_sdk.dart';
import 'package:test/test.dart';

class _RecordingProcessor implements LogRecordProcessor {
  _RecordingProcessor(
      {this.throwOnFlush = false, this.throwOnShutdown = false});

  final bool throwOnFlush;
  final bool throwOnShutdown;
  final List<LogRecord> emitted = [];
  int flushCount = 0;
  int shutdownCount = 0;

  @override
  void onEmit(LogRecord record) => emitted.add(record);

  @override
  Future<void> forceFlush() async {
    flushCount++;
    if (throwOnFlush) throw StateError('flush failed');
  }

  @override
  Future<void> shutdown() async {
    shutdownCount++;
    if (throwOnShutdown) throw StateError('shutdown failed');
  }
}

void main() {
  group('MultiLogRecordProcessor', () {
    test('fans out onEmit to every processor', () {
      final a = _RecordingProcessor();
      final b = _RecordingProcessor();
      final record = LogRecord(body: 'one');

      MultiLogRecordProcessor([a, b]).onEmit(record);

      expect(a.emitted, [record]);
      expect(b.emitted, [record]);
    });

    test('onEmit keeps going when one processor throws', () {
      final b = _RecordingProcessor();
      final multi = MultiLogRecordProcessor([_ThrowingOnEmit(), b]);

      expect(() => multi.onEmit(LogRecord(body: 'one')), returnsNormally);
      expect(b.emitted, hasLength(1));
    });

    test('forceFlush reaches every processor even if one throws', () async {
      final a = _RecordingProcessor(throwOnFlush: true);
      final b = _RecordingProcessor();

      await MultiLogRecordProcessor([a, b]).forceFlush();

      expect(a.flushCount, 1);
      expect(b.flushCount, 1);
    });

    test('shutdown reaches every processor even if one throws', () async {
      final a = _RecordingProcessor(throwOnShutdown: true);
      final b = _RecordingProcessor();

      await MultiLogRecordProcessor([a, b]).shutdown();

      expect(a.shutdownCount, 1);
      expect(b.shutdownCount, 1);
    });
  });
}

class _ThrowingOnEmit extends _RecordingProcessor {
  @override
  void onEmit(LogRecord record) => throw StateError('emit failed');
}
