import 'package:flutter_otel_sdk/flutter_otel_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_log_record_exporter.dart';
import 'support/fake_span_exporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await OTelSdk.reset();
  });

  group('OTelSdk singleton lifecycle', () {
    test('instance throws StateError before initialize is called', () {
      expect(() => OTelSdk.instance, throwsStateError);
    });

    test('maybeInstance is null before initialize is called', () {
      expect(OTelSdk.maybeInstance, isNull);
    });

    test('initialize sets both instance and maybeInstance', () async {
      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          logExporter: FakeLogRecordExporter(),
        ),
      );

      expect(OTelSdk.instance, same(sdk));
      expect(OTelSdk.maybeInstance, same(sdk));
    });

    test('reset clears the singleton and shuts down the previous instance',
        () async {
      final exporter = FakeLogRecordExporter();
      await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          logExporter: exporter,
        ),
      );

      await OTelSdk.reset();

      expect(OTelSdk.maybeInstance, isNull);
      expect(exporter.shutdownCallCount, 1);
    });
  });

  group('OTelSdk.getLogger passthrough', () {
    test('delegates to loggerProvider.getLogger', () async {
      final exporter = FakeLogRecordExporter();
      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          logExporter: exporter,
        ),
      );

      sdk.getLogger(name: 'my.logger').info('hello');
      await sdk.forceFlush();

      expect(exporter.allRecords.single.scopeName, 'my.logger');
    });
  });

  group('OTelSdk.getTracer passthrough', () {
    test('delegates to tracerProvider.getTracer', () async {
      final spanExporter = FakeSpanExporter();
      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          logExporter: FakeLogRecordExporter(),
          spanExporter: spanExporter,
        ),
      );

      sdk.getTracer(name: 'my.tracer').startSpan('op').end();
      await sdk.forceFlush();

      expect(spanExporter.allSpans.single.scopeName, 'my.tracer');
    });
  });

  group('OTelSdk trace-to-log correlation', () {
    test(
        'logger.info(...) called inside tracer.startActiveSpan(...) '
        'produces a LogRecord whose traceId/spanId match the active span',
        () async {
      final logExporter = FakeLogRecordExporter();
      final spanExporter = FakeSpanExporter();
      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          logExporter: logExporter,
          spanExporter: spanExporter,
        ),
      );

      SpanContext? activeContext;
      await sdk.getTracer().startActiveSpan('do-work', (span) async {
        activeContext = span.spanContext;
        sdk.getLogger().info('inside a span');
      });
      await sdk.forceFlush();

      final record = logExporter.allRecords.single;
      expect(record.traceId, isNotNull);
      expect(record.spanId, isNotNull);
      expect(record.traceId, activeContext!.traceId);
      expect(record.spanId, activeContext!.spanId);

      final span = spanExporter.allSpans.single;
      expect(span.spanContext, activeContext);
    });

    test('logs emitted outside any span carry no traceId/spanId', () async {
      final logExporter = FakeLogRecordExporter();
      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          logExporter: logExporter,
          spanExporter: FakeSpanExporter(),
        ),
      );

      sdk.getLogger().info('no span here');
      await sdk.forceFlush();

      final record = logExporter.allRecords.single;
      expect(record.traceId, isNull);
      expect(record.spanId, isNull);
    });
  });

  group('OTelSdk session tracking', () {
    test('sessionManager is non-null and session.id is merged by default',
        () async {
      final exporter = FakeLogRecordExporter();
      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          logExporter: exporter,
        ),
      );

      expect(sdk.sessionManager, isNotNull);

      sdk.getLogger().info('hello');
      await sdk.forceFlush();

      expect(exporter.allRecords.single.attributes['session.id'],
          sdk.sessionManager!.sessionId);
    });

    test('sessionManager is null and no session.id is added when disabled',
        () async {
      final exporter = FakeLogRecordExporter();
      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          sessionTrackingEnabled: false,
          logExporter: exporter,
        ),
      );

      expect(sdk.sessionManager, isNull);

      sdk.getLogger().info('hello');
      await sdk.forceFlush();

      expect(
        exporter.allRecords.single.attributes.containsKey('session.id'),
        isFalse,
      );
    });
  });

  group('OTelSdk enabled: false', () {
    test('makes zero HTTP calls even when an OTLP endpoint is configured',
        () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        return http.Response('ok', 200);
      });

      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          enabled: false,
          otlpEndpoint: Uri.parse('https://collector.example.com'),
          httpClient: client,
        ),
      );

      sdk.getLogger().info('one');
      sdk.getLogger().error('two');
      await sdk.forceFlush();

      expect(callCount, 0);
    });

    test('makes zero HTTP calls for traces either, even with spans started',
        () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        return http.Response('ok', 200);
      });

      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          enabled: false,
          otlpEndpoint: Uri.parse('https://collector.example.com'),
          httpClient: client,
        ),
      );

      sdk.getTracer().startSpan('op').end();
      await sdk.getTracer().startActiveSpan('op2', (span) async {});
      await sdk.forceFlush();

      expect(callCount, 0);
    });
  });

  group('OTelSdk OTLP endpoint resolution', () {
    test('enabled with no endpoint and no override exporter is a safe no-op',
        () async {
      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(resource: OTelResource(serviceName: 'test')),
      );

      // Should not throw even though there is nowhere to export to.
      sdk.getLogger().info('hello');
      await expectLater(sdk.forceFlush(), completes);
    });

    test(
        'otlpEndpoint is used to build a real OTLP exporter that posts to '
        '/v1/logs', () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response('ok', 200);
      });

      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          otlpEndpoint: Uri.parse('https://collector.example.com'),
          httpClient: client,
          scheduledDelay: const Duration(milliseconds: 10),
        ),
      );

      sdk.getLogger().info('hello');
      await sdk.forceFlush();

      expect(capturedUri, Uri.parse('https://collector.example.com/v1/logs'));
    });

    test('logExporter override bypasses otlpEndpoint entirely', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        return http.Response('ok', 200);
      });
      final fake = FakeLogRecordExporter();

      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          otlpEndpoint: Uri.parse('https://collector.example.com'),
          httpClient: client,
          logExporter: fake,
        ),
      );

      sdk.getLogger().info('hello');
      await sdk.forceFlush();

      expect(callCount, 0);
      expect(fake.allRecords, hasLength(1));
    });

    test(
        'otlpEndpoint is used to build a real OTLP span exporter that posts '
        'to /v1/traces', () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response('ok', 200);
      });

      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          otlpEndpoint: Uri.parse('https://collector.example.com'),
          httpClient: client,
          logExporter: FakeLogRecordExporter(),
          scheduledDelay: const Duration(milliseconds: 10),
        ),
      );

      sdk.getTracer().startSpan('op').end();
      await sdk.forceFlush();

      expect(
        capturedUri,
        Uri.parse('https://collector.example.com/v1/traces'),
      );
    });

    test('spanExporter override bypasses otlpEndpoint entirely', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        return http.Response('ok', 200);
      });
      final fake = FakeSpanExporter();

      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          otlpEndpoint: Uri.parse('https://collector.example.com'),
          httpClient: client,
          logExporter: FakeLogRecordExporter(),
          spanExporter: fake,
        ),
      );

      sdk.getTracer().startSpan('op').end();
      await sdk.forceFlush();

      expect(callCount, 0);
      expect(fake.allSpans, hasLength(1));
    });
  });

  group('OTelSdk.shutdown', () {
    test(
        'flushes, shuts down the processor, and disposes the session '
        'manager', () async {
      final exporter = FakeLogRecordExporter();
      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          logExporter: exporter,
        ),
      );

      sdk.getLogger().info('hello');
      await sdk.shutdown();

      expect(exporter.allRecords, hasLength(1));
      expect(exporter.shutdownCallCount, 1);
    });

    test('also flushes and shuts down the span pipeline', () async {
      final spanExporter = FakeSpanExporter();
      final sdk = await OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          logExporter: FakeLogRecordExporter(),
          spanExporter: spanExporter,
        ),
      );

      sdk.getTracer().startSpan('op').end();
      await sdk.shutdown();

      expect(spanExporter.allSpans, hasLength(1));
      expect(spanExporter.shutdownCallCount, 1);
    });
  });
}
