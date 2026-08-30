import 'package:flutter_otel_sdk/flutter_otel_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_log_record_exporter.dart';

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
  });
}
