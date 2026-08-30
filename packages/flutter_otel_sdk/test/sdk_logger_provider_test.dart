import 'package:flutter_otel_sdk/flutter_otel_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_log_record_exporter.dart';

class _FakeSessionManager implements SessionManager {
  _FakeSessionManager(this._id);

  final String _id;
  int touchCallCount = 0;

  @override
  String get sessionId => _id;

  @override
  void touch() => touchCallCount++;
}

void main() {
  late FakeLogRecordExporter exporter;
  late OTelResource resource;

  setUp(() {
    exporter = FakeLogRecordExporter();
    resource = OTelResource(serviceName: 'test');
  });

  group('SdkLoggerProvider without session tracking', () {
    test('does not add session.id and does not require a SessionManager',
        () async {
      final processor = SimpleLogRecordProcessor(exporter, resource);
      final provider = SdkLoggerProvider(
        resource: resource,
        processor: processor,
      );

      provider.getLogger().info('hello');
      await processor.forceFlush();

      expect(exporter.allRecords.single.attributes.containsKey('session.id'),
          isFalse);
    });
  });

  group('SdkLoggerProvider with session tracking', () {
    test('merges session.id onto every emitted record', () async {
      final processor = SimpleLogRecordProcessor(exporter, resource);
      final sessionManager = _FakeSessionManager('session-abc');
      final provider = SdkLoggerProvider(
        resource: resource,
        processor: processor,
        sessionManager: sessionManager,
      );

      provider.getLogger().info('hello');
      await processor.forceFlush();

      expect(
          exporter.allRecords.single.attributes['session.id'], 'session-abc');
    });

    test('calls touch() on every emit', () async {
      final processor = SimpleLogRecordProcessor(exporter, resource);
      final sessionManager = _FakeSessionManager('session-abc');
      final provider = SdkLoggerProvider(
        resource: resource,
        processor: processor,
        sessionManager: sessionManager,
      );
      final logger = provider.getLogger();

      logger.info('one');
      logger.warn('two');
      await processor.forceFlush();

      expect(sessionManager.touchCallCount, 2);
    });

    test('caller-supplied session.id attribute wins over the injected one',
        () async {
      final processor = SimpleLogRecordProcessor(exporter, resource);
      final sessionManager = _FakeSessionManager('session-abc');
      final provider = SdkLoggerProvider(
        resource: resource,
        processor: processor,
        sessionManager: sessionManager,
      );

      provider.getLogger().emit(
            LogRecord(body: 'hi', attributes: {'session.id': 'explicit'}),
          );
      await processor.forceFlush();

      expect(exporter.allRecords.single.attributes['session.id'], 'explicit');
    });
  });

  group('SdkLoggerProvider.getLogger', () {
    test('stamps the requested name/version as the record scope', () async {
      final processor = SimpleLogRecordProcessor(exporter, resource);
      final provider =
          SdkLoggerProvider(resource: resource, processor: processor);

      provider.getLogger(name: 'my.scope', version: '9.9.9').info('scoped');
      await processor.forceFlush();

      final record = exporter.allRecords.single;
      expect(record.scopeName, 'my.scope');
      expect(record.scopeVersion, '9.9.9');
    });

    test('returns the same Logger instance for the same name/version', () {
      final processor = SimpleLogRecordProcessor(exporter, resource);
      final provider =
          SdkLoggerProvider(resource: resource, processor: processor);

      final a = provider.getLogger(name: 'foo', version: '1.0.0');
      final b = provider.getLogger(name: 'foo', version: '1.0.0');
      final c = provider.getLogger(name: 'bar');

      expect(identical(a, b), isTrue);
      expect(identical(a, c), isFalse);
    });

    test(
        'does not collide for name/version pairs that would collide under a '
        'delimiter-joined string key', () {
      final processor = SimpleLogRecordProcessor(exporter, resource);
      final provider =
          SdkLoggerProvider(resource: resource, processor: processor);

      // Both of these would join to the same string under a naive
      // '$name:$version' (or '$name@$version') cache key.
      final a = provider.getLogger(name: 'a:b', version: 'c');
      final b = provider.getLogger(name: 'a', version: 'b:c');

      expect(identical(a, b), isFalse);
    });

    test('forceFlush and shutdown delegate to the processor', () async {
      final processor = SimpleLogRecordProcessor(exporter, resource);
      final provider =
          SdkLoggerProvider(resource: resource, processor: processor);

      provider.getLogger().info('hello');
      await provider.forceFlush();
      expect(exporter.exportedBatches, hasLength(1));

      await provider.shutdown();
      expect(exporter.shutdownCallCount, 1);
    });
  });
}
