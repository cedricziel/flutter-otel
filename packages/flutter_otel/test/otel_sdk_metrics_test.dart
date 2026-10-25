import 'package:flutter_otel/flutter_otel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_metric_exporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final resource = OTelResource(serviceName: 'test', serviceVersion: '1.0');

  tearDown(() async {
    await OTelSdk.reset();
  });

  Future<OTelSdk> initialize({
    bool enabled = true,
    Uri? otlpEndpoint,
    Uri? otlpMetricsEndpoint,
    Map<String, String> otlpHeaders = const {},
    http.Client? httpClient,
    MetricExporter? metricExporter,
    Redactor? redactor,
  }) =>
      OTelSdk.initialize(
        OTelSdkConfig(
          resource: resource,
          enabled: enabled,
          sessionTrackingEnabled: false,
          otlpEndpoint: otlpEndpoint,
          otlpMetricsEndpoint: otlpMetricsEndpoint,
          otlpHeaders: otlpHeaders,
          httpClient: httpClient,
          metricExporter: metricExporter,
          redactor: redactor,
        ),
      );

  group('OTelSdk metrics', () {
    test('getMeter records into the pipeline and forceFlush exports it',
        () async {
      final exporter = FakeMetricExporter();
      final sdk = await initialize(metricExporter: exporter);

      sdk.getMeter(name: 'my.meter').createCounter('requests').add(2);
      await sdk.forceFlush();

      final metric = exporter.exportedBatches.single.single as SumMetricData;
      expect(metric.name, 'requests');
      expect(metric.scopeName, 'my.meter');
      expect(metric.points.single.value, 2);
    });

    test('shares the resource with the other signals', () async {
      final exporter = FakeMetricExporter();
      final sdk = await initialize(metricExporter: exporter);

      sdk.getMeter().createCounter('requests').add(1);
      await sdk.forceFlush();

      expect(exporter.resources.single, same(resource));
    });

    test('redacts metric attributes when a redactor is set', () async {
      final exporter = FakeMetricExporter();
      final sdk = await initialize(
        metricExporter: exporter,
        redactor: PatternRedactor(),
      );

      sdk.getMeter().createCounter('requests').add(
        1,
        attributes: {'url': 'https://root:pw@nas.local/api'},
      );
      await sdk.forceFlush();

      final metric = exporter.exportedBatches.single.single;
      expect(
        metric.points.single.attributes['url'],
        'https://[REDACTED]@nas.local/api',
      );
    });

    test('shutdown exports pending metrics and shuts the exporter down',
        () async {
      final exporter = FakeMetricExporter();
      final sdk = await initialize(metricExporter: exporter);

      sdk.getMeter().createCounter('requests').add(1);
      await sdk.shutdown();

      expect(exporter.exportedBatches, isNotEmpty);
      expect(exporter.shutdownCallCount, 1);
    });

    test('otlpEndpoint builds an exporter that posts to /v1/metrics', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('ok', 200);
      });
      final sdk = await initialize(
        otlpEndpoint: Uri.parse('https://collector.example.com'),
        otlpHeaders: {'Authorization': 'Bearer token'},
        httpClient: client,
      );

      sdk.getMeter().createCounter('requests').add(1);
      await sdk.forceFlush();

      expect(
        requests.single.url,
        Uri.parse('https://collector.example.com/v1/metrics'),
      );
      expect(requests.single.headers['authorization'], 'Bearer token');
    });

    test('otlpMetricsEndpoint is used verbatim', () async {
      Uri? captured;
      final client = MockClient((request) async {
        captured = request.url;
        return http.Response('ok', 200);
      });
      final sdk = await initialize(
        otlpEndpoint: Uri.parse('https://collector.example.com'),
        otlpMetricsEndpoint: Uri.parse('https://metrics.example.com/custom'),
        httpClient: client,
      );

      sdk.getMeter().createCounter('requests').add(1);
      await sdk.forceFlush();

      expect(captured, Uri.parse('https://metrics.example.com/custom'));
    });

    test('metricExporter override bypasses otlpEndpoint entirely', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('ok', 200);
      });
      final exporter = FakeMetricExporter();
      final sdk = await initialize(
        otlpEndpoint: Uri.parse('https://collector.example.com'),
        httpClient: client,
        metricExporter: exporter,
      );

      sdk.getMeter().createCounter('requests').add(1);
      await sdk.forceFlush();

      expect(calls, 0);
      expect(exporter.exportedBatches, hasLength(1));
    });

    test('is a no-op without an endpoint or exporter', () async {
      final sdk = await initialize();

      expect(sdk.meterProvider, isA<NoopMeterProvider>());
      sdk.getMeter().createCounter('requests').add(1);
      await expectLater(sdk.forceFlush(), completes);
    });

    test('is a no-op when disabled, even with an endpoint or exporter',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('ok', 200);
      });
      final exporter = FakeMetricExporter();
      final sdk = await initialize(
        enabled: false,
        otlpEndpoint: Uri.parse('https://collector.example.com'),
        httpClient: client,
        metricExporter: exporter,
      );

      sdk.getMeter().createCounter('requests').add(1);
      await sdk.forceFlush();
      await sdk.shutdown();

      expect(sdk.meterProvider, isA<NoopMeterProvider>());
      expect(calls, 0);
      expect(exporter.exportedBatches, isEmpty);
    });
  });
}
