import 'dart:convert';
import 'dart:io';

import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:dart_otel_exporter_otlp_http/dart_otel_exporter_otlp_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final _start = DateTime.utc(2024, 1, 1);
final _end = DateTime.utc(2024, 1, 1, 0, 1);

NumberDataPoint _number(num value,
        [Map<String, Object?> attributes = const {}]) =>
    NumberDataPoint(
      attributes: attributes,
      startTime: _start,
      time: _end,
      value: value,
    );

SumMetricData _sum({
  String name = 'requests',
  String scope = 'scope',
  String? scopeVersion,
  bool isMonotonic = true,
  num value = 1,
}) =>
    SumMetricData(
      name: name,
      description: null,
      unit: null,
      scopeName: scope,
      scopeVersion: scopeVersion,
      isMonotonic: isMonotonic,
      points: [_number(value)],
    );

void main() {
  group('OtlpHttpMetricExporter.resolveMetricsEndpoint', () {
    test('uses the explicit metrics endpoint verbatim when set', () {
      final resolved = OtlpHttpMetricExporter.resolveMetricsEndpoint(
        baseEndpoint: Uri.parse('https://collector.example.com'),
        metricsEndpoint: Uri.parse('https://metrics.example.com/custom'),
      );
      expect(resolved, Uri.parse('https://metrics.example.com/custom'));
    });

    test('appends /v1/metrics to the base endpoint', () {
      final resolved = OtlpHttpMetricExporter.resolveMetricsEndpoint(
        baseEndpoint: Uri.parse('https://collector.example.com'),
      );
      expect(resolved, Uri.parse('https://collector.example.com/v1/metrics'));
    });

    test('handles a base endpoint with a trailing slash', () {
      final resolved = OtlpHttpMetricExporter.resolveMetricsEndpoint(
        baseEndpoint: Uri.parse('https://collector.example.com/'),
      );
      expect(resolved, Uri.parse('https://collector.example.com/v1/metrics'));
    });

    test('returns null when neither endpoint is set', () {
      expect(OtlpHttpMetricExporter.resolveMetricsEndpoint(), isNull);
    });
  });

  group('OtlpHttpMetricExporter.export', () {
    late Uri capturedUri;
    late Map<String, String> capturedHeaders;
    late String capturedBody;
    late int callCount;

    http.Client buildClient(int statusCode, {String body = 'ok'}) {
      return MockClient((request) async {
        callCount++;
        capturedUri = request.url;
        capturedHeaders = request.headers;
        capturedBody = request.body;
        return http.Response(body, statusCode);
      });
    }

    OtlpHttpMetricExporter newExporter(
      http.Client client, {
      Map<String, String> headers = const {},
      bool ownsClient = false,
    }) =>
        OtlpHttpMetricExporter(
          endpoint: Uri.parse('https://collector.example.com/v1/metrics'),
          httpClient: client,
          headers: headers,
          ownsClient: ownsClient,
        );

    final resource = OTelResource(serviceName: 'trueapp');

    setUp(() {
      callCount = 0;
    });

    test('POSTs the golden OTLP JSON payload with the configured headers',
        () async {
      final exporter = newExporter(
        buildClient(200),
        headers: {'Authorization': 'Bearer token'},
      );
      final metrics = <MetricData>[
        SumMetricData(
          name: 'http.requests',
          description: 'Requests served',
          unit: '1',
          scopeName: 'my.meter',
          scopeVersion: '2.0.0',
          isMonotonic: true,
          points: [
            _number(5, {'http.method': 'GET'})
          ],
        ),
        SumMetricData(
          name: 'queue.depth',
          description: null,
          unit: null,
          scopeName: 'my.meter',
          scopeVersion: '2.0.0',
          isMonotonic: false,
          points: [_number(-1.5)],
        ),
        HistogramMetricData(
          name: 'http.duration',
          description: null,
          unit: 'ms',
          scopeName: 'my.meter',
          scopeVersion: '2.0.0',
          points: [
            HistogramDataPoint(
              attributes: const {},
              startTime: _start,
              time: _end,
              count: 3,
              sum: 30.5,
              min: 4,
              max: 16.5,
              bucketCounts: const [1, 1, 1],
              explicitBounds: const [5, 10],
            ),
          ],
        ),
        GaugeMetricData(
          name: 'battery.level',
          description: null,
          unit: null,
          scopeName: 'other.meter',
          scopeVersion: null,
          points: [_number(87)],
        ),
      ];

      final result = await exporter.export(
        metrics,
        OTelResource(serviceName: 'trueapp', serviceVersion: '1.0.0'),
      );

      expect(result.success, isTrue);
      expect(callCount, 1);
      expect(
        capturedUri,
        Uri.parse('https://collector.example.com/v1/metrics'),
      );
      expect(capturedHeaders['content-type'], 'application/json');
      expect(capturedHeaders['authorization'], 'Bearer token');
      final golden = jsonDecode(
        File('test/golden/metrics_request.json').readAsStringSync(),
      );
      expect(jsonDecode(capturedBody), golden);
    });

    test('groups metrics by scope name and version', () async {
      final exporter = newExporter(buildClient(200));

      await exporter.export([
        _sum(name: 'a', scope: 'one'),
        _sum(name: 'b', scope: 'two'),
        _sum(name: 'c', scope: 'one'),
        _sum(name: 'd', scope: 'one', scopeVersion: '1'),
      ], resource);

      final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
      final scopeMetrics = ((decoded['resourceMetrics'] as List).single
          as Map<String, dynamic>)['scopeMetrics'] as List;
      expect(scopeMetrics, hasLength(3));
      expect(
        [for (final s in scopeMetrics) (s['metrics'] as List).length],
        [2, 1, 1],
      );
    });

    test('encodes integer values as strings and doubles as numbers', () async {
      final exporter = newExporter(buildClient(200));

      await exporter.export([
        _sum(name: 'i', value: 3),
        _sum(name: 'd', value: 2.5),
        _sum(name: 'whole', value: 2.0),
      ], resource);

      final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
      final metrics = (((decoded['resourceMetrics'] as List).single
              as Map<String, dynamic>)['scopeMetrics'] as List)
          .single['metrics'] as List;
      final points = [
        for (final m in metrics) (m['sum']['dataPoints'] as List).single,
      ];
      expect(points[0]['asInt'], '3');
      expect(points[1]['asDouble'], 2.5);
      expect(points[2]['asDouble'], 2.0);
      expect(points[2].containsKey('asInt'), isFalse);
    });

    test('omits histogram min and max when absent', () async {
      final exporter = newExporter(buildClient(200));

      await exporter.export([
        HistogramMetricData(
          name: 'h',
          description: null,
          unit: null,
          scopeName: 'scope',
          scopeVersion: null,
          points: [
            HistogramDataPoint(
              attributes: const {},
              startTime: _start,
              time: _end,
              count: 0,
              sum: 0,
              min: null,
              max: null,
              bucketCounts: const [0],
              explicitBounds: const [],
            ),
          ],
        ),
      ], resource);

      final point = (jsonDecode(capturedBody)['resourceMetrics'][0]
                  ['scopeMetrics'][0]['metrics'][0]['histogram']['dataPoints']
              as List)
          .single as Map<String, dynamic>;
      expect(point.containsKey('min'), isFalse);
      expect(point.containsKey('max'), isFalse);
    });

    test('returns success for an empty batch without any HTTP call', () async {
      final exporter = newExporter(buildClient(200));

      final result = await exporter.export([], resource);

      expect(result.success, isTrue);
      expect(callCount, 0);
    });

    test('treats a non-2xx response as a failure', () async {
      final exporter = newExporter(buildClient(500, body: 'server error'));

      final result = await exporter.export([_sum()], resource);

      expect(result.success, isFalse);
      expect(result.error, contains('500'));
    });

    test('treats a thrown exception as a failure instead of rethrowing',
        () async {
      final exporter = newExporter(
        MockClient((request) async => throw const _ClientException()),
      );

      final result = await exporter.export([_sum()], resource);

      expect(result.success, isFalse);
      expect(result.error, isA<_ClientException>());
    });

    test('a custom Content-Type header cannot override the JSON content type',
        () async {
      final exporter = newExporter(
        buildClient(200),
        headers: const {'Content-Type': 'text/plain'},
      );

      await exporter.export([_sum()], resource);

      expect(capturedHeaders['content-type'], 'application/json');
    });

    test('shutdown closes the client only when it owns it', () async {
      var closed = 0;
      final client = _CloseTrackingClient(onClose: () => closed++);

      await newExporter(client).shutdown();
      expect(closed, 0);

      await newExporter(client, ownsClient: true).shutdown();
      expect(closed, 1);
    });
  });
}

class _ClientException implements Exception {
  const _ClientException();
}

class _CloseTrackingClient extends http.BaseClient {
  _CloseTrackingClient({required this.onClose});

  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => onClose();
}
