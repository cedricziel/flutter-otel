import 'dart:convert';

import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:flutter_otel_exporter_otlp_http/flutter_otel_exporter_otlp_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('OtlpHttpSpanExporter.resolveTracesEndpoint', () {
    test('uses the explicit traces endpoint verbatim when set', () {
      final resolved = OtlpHttpSpanExporter.resolveTracesEndpoint(
        baseEndpoint: Uri.parse('https://collector.example.com'),
        tracesEndpoint: Uri.parse('https://traces.example.com/custom'),
      );
      expect(resolved, Uri.parse('https://traces.example.com/custom'));
    });

    test('appends /v1/traces to the base endpoint when no override is set', () {
      final resolved = OtlpHttpSpanExporter.resolveTracesEndpoint(
        baseEndpoint: Uri.parse('https://collector.example.com'),
      );
      expect(resolved, Uri.parse('https://collector.example.com/v1/traces'));
    });

    test('handles a base endpoint with a trailing slash', () {
      final resolved = OtlpHttpSpanExporter.resolveTracesEndpoint(
        baseEndpoint: Uri.parse('https://collector.example.com/'),
      );
      expect(resolved, Uri.parse('https://collector.example.com/v1/traces'));
    });

    test('returns null when neither endpoint is set', () {
      expect(OtlpHttpSpanExporter.resolveTracesEndpoint(), isNull);
    });
  });

  group('OtlpHttpSpanExporter.export', () {
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

    setUp(() {
      callCount = 0;
    });

    SpanData buildSpan({
      String name = 'op',
      SpanKind kind = SpanKind.server,
      String? parentSpanId,
      StatusCode statusCode = StatusCode.ok,
      String? statusDescription,
      Map<String, Object?> attributes = const {},
      List<SpanEvent> events = const [],
      List<SpanLink> links = const [],
      String scopeName = 'my.tracer',
      String? scopeVersion = '2.0.0',
    }) =>
        SpanData(
          name: name,
          spanContext: const SpanContext(
            traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            spanId: 'bbbbbbbbbbbbbbbb',
          ),
          parentSpanId: parentSpanId,
          kind: kind,
          startTime: DateTime.utc(2024, 1, 1),
          endTime: DateTime.utc(2024, 1, 1, 0, 0, 1),
          attributes: attributes,
          events: events,
          links: links,
          statusCode: statusCode,
          statusDescription: statusDescription,
          scopeName: scopeName,
          scopeVersion: scopeVersion,
        );

    test('POSTs the OTLP JSON body shape to the resolved endpoint', () async {
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: buildClient(200),
        headers: {'Authorization': 'Bearer token'},
      );
      final resource = OTelResource(
        serviceName: 'trueapp',
        serviceVersion: '1.0.0',
      );
      final span = buildSpan(
        parentSpanId: 'cccccccccccccccc',
        attributes: {'http.method': 'GET', 'retry': 2},
        events: [
          SpanEvent(
            name: 'checkpoint',
            timestamp: DateTime.utc(2024, 1, 1, 0, 0, 0, 500),
            attributes: {'k': 'v'},
          ),
        ],
        statusDescription: 'all good',
      );

      final result = await exporter.export([span], resource);

      expect(result.success, isTrue);
      expect(callCount, 1);
      expect(
        capturedUri,
        Uri.parse('https://collector.example.com/v1/traces'),
      );
      expect(capturedHeaders['content-type'], contains('application/json'));
      expect(capturedHeaders['authorization'], 'Bearer token');

      final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
      final resourceSpans = decoded['resourceSpans'] as List;
      expect(resourceSpans, hasLength(1));

      final resourceSpan = resourceSpans.single as Map<String, dynamic>;
      final resourceAttrs = (resourceSpan['resource']
          as Map<String, dynamic>)['attributes'] as List;
      expect(
        resourceAttrs,
        contains(
          equals({
            'key': 'service.name',
            'value': {'stringValue': 'trueapp'},
          }),
        ),
      );

      final scopeSpans = resourceSpan['scopeSpans'] as List;
      expect(scopeSpans, hasLength(1));
      final scopeSpan = scopeSpans.single as Map<String, dynamic>;
      expect(scopeSpan['scope'], {'name': 'my.tracer', 'version': '2.0.0'});

      final spans = scopeSpan['spans'] as List;
      expect(spans, hasLength(1));
      final encoded = spans.single as Map<String, dynamic>;

      expect(encoded['traceId'], 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(encoded['spanId'], 'bbbbbbbbbbbbbbbb');
      expect(encoded['parentSpanId'], 'cccccccccccccccc');
      expect(encoded['name'], 'op');
      expect(encoded['kind'], 2); // SpanKind.server -> OTLP SERVER (2)
      expect(encoded['startTimeUnixNano'], '1704067200000000000');
      expect(encoded['endTimeUnixNano'], '1704067201000000000');
      expect(
        encoded['attributes'],
        containsAll([
          {
            'key': 'http.method',
            'value': {'stringValue': 'GET'},
          },
          {
            'key': 'retry',
            'value': {'intValue': '2'},
          },
        ]),
      );

      final events = encoded['events'] as List;
      expect(events, hasLength(1));
      final event = events.single as Map<String, dynamic>;
      expect(event['name'], 'checkpoint');
      expect(event['timeUnixNano'], '1704067200500000000');
      expect(event['attributes'], [
        {
          'key': 'k',
          'value': {'stringValue': 'v'},
        },
      ]);

      expect(encoded['status'], {'code': 1, 'message': 'all good'});
    });

    test('omits parentSpanId for a root span', () async {
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: buildClient(200),
      );
      await exporter.export(
        [buildSpan()],
        OTelResource(serviceName: 'trueapp'),
      );

      final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
      final span = ((decoded['resourceSpans'] as List).single
              as Map<String, dynamic>)['scopeSpans']
          .first['spans']
          .first as Map<String, dynamic>;
      expect(span.containsKey('parentSpanId'), isFalse);
    });

    test('encodes links as traceId/spanId/attributes triples', () async {
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: buildClient(200),
      );
      await exporter.export(
        [
          buildSpan(
            links: [
              SpanLink(
                const SpanContext(
                  traceId: 'dddddddddddddddddddddddddddddddd',
                  spanId: 'eeeeeeeeeeeeeeee',
                ),
                attributes: {'ws.connection.id': 'c1'},
              ),
            ],
          ),
        ],
        OTelResource(serviceName: 'trueapp'),
      );

      final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
      final span = ((decoded['resourceSpans'] as List).single
              as Map<String, dynamic>)['scopeSpans']
          .first['spans']
          .first as Map<String, dynamic>;
      expect(span['links'], [
        {
          'traceId': 'dddddddddddddddddddddddddddddddd',
          'spanId': 'eeeeeeeeeeeeeeee',
          'attributes': [
            {
              'key': 'ws.connection.id',
              'value': {'stringValue': 'c1'},
            },
          ],
        },
      ]);
    });

    test('omits the links field entirely when there are none', () async {
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: buildClient(200),
      );
      await exporter.export(
        [buildSpan()],
        OTelResource(serviceName: 'trueapp'),
      );

      final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
      final span = ((decoded['resourceSpans'] as List).single
              as Map<String, dynamic>)['scopeSpans']
          .first['spans']
          .first as Map<String, dynamic>;
      expect(span.containsKey('links'), isFalse);
    });

    test('omits status message when statusDescription is null', () async {
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: buildClient(200),
      );
      await exporter.export(
        [buildSpan(statusCode: StatusCode.unset)],
        OTelResource(serviceName: 'trueapp'),
      );

      final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
      final span = ((decoded['resourceSpans'] as List).single
              as Map<String, dynamic>)['scopeSpans']
          .first['spans']
          .first as Map<String, dynamic>;
      expect(span['status'], {'code': 0});
    });

    test('maps every SpanKind to its OTLP integer 1:1', () async {
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: buildClient(200),
      );
      const expected = {
        SpanKind.internal: 1,
        SpanKind.server: 2,
        SpanKind.client: 3,
        SpanKind.producer: 4,
        SpanKind.consumer: 5,
      };

      for (final entry in expected.entries) {
        await exporter.export(
          [buildSpan(kind: entry.key)],
          OTelResource(serviceName: 'trueapp'),
        );
        final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
        final span = ((decoded['resourceSpans'] as List).single
                as Map<String, dynamic>)['scopeSpans']
            .first['spans']
            .first as Map<String, dynamic>;
        expect(span['kind'], entry.value, reason: '${entry.key}');
      }
    });

    test('maps every StatusCode to its OTLP integer 1:1', () async {
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: buildClient(200),
      );
      const expected = {
        StatusCode.unset: 0,
        StatusCode.ok: 1,
        StatusCode.error: 2,
      };

      for (final entry in expected.entries) {
        await exporter.export(
          [buildSpan(statusCode: entry.key)],
          OTelResource(serviceName: 'trueapp'),
        );
        final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
        final span = ((decoded['resourceSpans'] as List).single
                as Map<String, dynamic>)['scopeSpans']
            .first['spans']
            .first as Map<String, dynamic>;
        expect(span['status'], {'code': entry.value}, reason: '${entry.key}');
      }
    });

    test('groups spans by instrumentation scope into separate scopeSpans',
        () async {
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: buildClient(200),
      );
      final spans = [
        buildSpan(scopeName: 'scope.one'),
        buildSpan(scopeName: 'scope.two'),
        buildSpan(scopeName: 'scope.one'),
      ];

      await exporter.export(spans, OTelResource(serviceName: 'trueapp'));

      final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
      final scopeSpans =
          (decoded['resourceSpans'] as List).single as Map<String, dynamic>;
      final scopes = (scopeSpans['scopeSpans'] as List)
          .map((s) => (s as Map<String, dynamic>)['scope'])
          .toList();
      expect(scopes, hasLength(2));
    });

    test('returns success for an empty batch without any HTTP call', () async {
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: buildClient(200),
      );

      final result = await exporter.export([], OTelResource(serviceName: 'x'));

      expect(result.success, isTrue);
      expect(callCount, 0);
    });

    test('treats a non-2xx response as a failure', () async {
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: buildClient(500, body: 'server error'),
      );

      final result = await exporter.export(
        [buildSpan()],
        OTelResource(serviceName: 'trueapp'),
      );

      expect(result.success, isFalse);
      expect(result.error, contains('500'));
    });

    test('treats a thrown exception as a failure instead of rethrowing',
        () async {
      final throwingClient = MockClient((request) async {
        throw const SocketExceptionStub();
      });
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: throwingClient,
      );

      final result = await exporter.export(
        [buildSpan()],
        OTelResource(serviceName: 'trueapp'),
      );

      expect(result.success, isFalse);
      expect(result.error, isA<SocketExceptionStub>());
    });

    test(
        "a custom 'Content-Type' header in config cannot override the "
        'required OTLP JSON content type', () async {
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: buildClient(200),
        headers: const {'Content-Type': 'text/plain'},
      );

      await exporter.export(
        [buildSpan()],
        OTelResource(serviceName: 'trueapp'),
      );

      expect(capturedHeaders['content-type'], 'application/json');
    });

    test('shutdown does not close an externally-owned client', () async {
      var closeCalled = false;
      final client = _CloseTrackingClient(
        MockClient((request) async => http.Response('ok', 200)),
        onClose: () => closeCalled = true,
      );
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: client,
      );

      await exporter.shutdown();

      expect(closeCalled, isFalse);
    });

    test('shutdown closes the client when ownsClient is true', () async {
      var closeCalled = false;
      final client = _CloseTrackingClient(
        MockClient((request) async => http.Response('ok', 200)),
        onClose: () => closeCalled = true,
      );
      final exporter = OtlpHttpSpanExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/traces'),
        httpClient: client,
        ownsClient: true,
      );

      await exporter.shutdown();

      expect(closeCalled, isTrue);
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

class _CloseTrackingClient extends http.BaseClient {
  _CloseTrackingClient(this._inner, {required this.onClose});

  final http.Client _inner;
  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    onClose();
    _inner.close();
  }
}
