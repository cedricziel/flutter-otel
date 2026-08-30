import 'dart:convert';

import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:flutter_otel_exporter_otlp_http/flutter_otel_exporter_otlp_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('OtlpHttpLogExporter.resolveLogsEndpoint', () {
    test('uses the explicit logs endpoint verbatim when set', () {
      final resolved = OtlpHttpLogExporter.resolveLogsEndpoint(
        baseEndpoint: Uri.parse('https://collector.example.com'),
        logsEndpoint: Uri.parse('https://logs.example.com/custom'),
      );
      expect(resolved, Uri.parse('https://logs.example.com/custom'));
    });

    test('appends /v1/logs to the base endpoint when no override is set', () {
      final resolved = OtlpHttpLogExporter.resolveLogsEndpoint(
        baseEndpoint: Uri.parse('https://collector.example.com'),
      );
      expect(resolved, Uri.parse('https://collector.example.com/v1/logs'));
    });

    test('handles a base endpoint with a trailing slash', () {
      final resolved = OtlpHttpLogExporter.resolveLogsEndpoint(
        baseEndpoint: Uri.parse('https://collector.example.com/'),
      );
      expect(resolved, Uri.parse('https://collector.example.com/v1/logs'));
    });

    test('returns null when neither endpoint is set', () {
      expect(OtlpHttpLogExporter.resolveLogsEndpoint(), isNull);
    });
  });

  group('OtlpHttpLogExporter.export', () {
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

    test('POSTs the OTLP JSON body shape to the resolved endpoint', () async {
      final exporter = OtlpHttpLogExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/logs'),
        httpClient: buildClient(200),
        headers: {'Authorization': 'Bearer token'},
      );
      final resource = OTelResource(
        serviceName: 'trueapp',
        serviceVersion: '1.0.0',
      );
      final record = LogRecord(
        body: 'hello world',
        severity: LogSeverity.warn,
        timestamp: DateTime.utc(2024, 1, 1),
        attributes: {'session.id': 'abc-123', 'retry': 2},
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        spanId: 'bbbbbbbbbbbbbbbb',
        scopeName: 'my.logger',
        scopeVersion: '2.0.0',
      );

      final result = await exporter.export([record], resource);

      expect(result.success, isTrue);
      expect(callCount, 1);
      expect(capturedUri, Uri.parse('https://collector.example.com/v1/logs'));
      expect(capturedHeaders['content-type'], contains('application/json'));
      expect(capturedHeaders['authorization'], 'Bearer token');

      final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
      final resourceLogs = decoded['resourceLogs'] as List;
      expect(resourceLogs, hasLength(1));

      final resourceLog = resourceLogs.single as Map<String, dynamic>;
      final resourceAttrs = (resourceLog['resource']
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
      expect(
        resourceAttrs,
        contains(
          equals({
            'key': 'service.version',
            'value': {'stringValue': '1.0.0'},
          }),
        ),
      );

      final scopeLogs = resourceLog['scopeLogs'] as List;
      expect(scopeLogs, hasLength(1));
      final scopeLog = scopeLogs.single as Map<String, dynamic>;
      expect(scopeLog['scope'], {'name': 'my.logger', 'version': '2.0.0'});

      final logRecords = scopeLog['logRecords'] as List;
      expect(logRecords, hasLength(1));
      final encoded = logRecords.single as Map<String, dynamic>;

      expect(encoded['timeUnixNano'], '1704067200000000000');
      expect(encoded['observedTimeUnixNano'], '1704067200000000000');
      expect(encoded['severityNumber'], 13);
      expect(encoded['severityText'], 'WARN');
      expect(encoded['body'], {'stringValue': 'hello world'});
      expect(encoded['traceId'], 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(encoded['spanId'], 'bbbbbbbbbbbbbbbb');
      expect(
        encoded['attributes'],
        containsAll([
          {
            'key': 'session.id',
            'value': {'stringValue': 'abc-123'},
          },
          {
            'key': 'retry',
            'value': {'intValue': '2'},
          },
        ]),
      );
    });

    test('groups records by instrumentation scope into separate scopeLogs',
        () async {
      final exporter = OtlpHttpLogExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/logs'),
        httpClient: buildClient(200),
      );
      final resource = OTelResource(serviceName: 'trueapp');
      final records = [
        LogRecord(body: 'a', scopeName: 'scope.one'),
        LogRecord(body: 'b', scopeName: 'scope.two'),
        LogRecord(body: 'c', scopeName: 'scope.one'),
      ];

      await exporter.export(records, resource);

      final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
      final scopeLogs =
          (decoded['resourceLogs'] as List).single as Map<String, dynamic>;
      final scopes = (scopeLogs['scopeLogs'] as List)
          .map((s) => (s as Map<String, dynamic>)['scope'])
          .toList();
      expect(scopes, hasLength(2));
    });

    test('omits traceId/spanId when not present on the record', () async {
      final exporter = OtlpHttpLogExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/logs'),
        httpClient: buildClient(200),
      );
      await exporter.export(
        [LogRecord(body: 'no correlation')],
        OTelResource(serviceName: 'trueapp'),
      );

      final decoded = jsonDecode(capturedBody) as Map<String, dynamic>;
      final logRecord = ((decoded['resourceLogs'] as List).single
              as Map<String, dynamic>)['scopeLogs']
          .first['logRecords']
          .first as Map<String, dynamic>;
      expect(logRecord.containsKey('traceId'), isFalse);
      expect(logRecord.containsKey('spanId'), isFalse);
    });

    test('returns success for an empty batch without any HTTP call', () async {
      final exporter = OtlpHttpLogExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/logs'),
        httpClient: buildClient(200),
      );

      final result = await exporter.export([], OTelResource(serviceName: 'x'));

      expect(result.success, isTrue);
      expect(callCount, 0);
    });

    test('treats a non-2xx response as a failure', () async {
      final exporter = OtlpHttpLogExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/logs'),
        httpClient: buildClient(500, body: 'server error'),
      );

      final result = await exporter.export(
        [LogRecord(body: 'x')],
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
      final exporter = OtlpHttpLogExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/logs'),
        httpClient: throwingClient,
      );

      final result = await exporter.export(
        [LogRecord(body: 'x')],
        OTelResource(serviceName: 'trueapp'),
      );

      expect(result.success, isFalse);
      expect(result.error, isA<SocketExceptionStub>());
    });

    test(
        "a custom 'Content-Type' header in config cannot override the "
        'required OTLP JSON content type', () async {
      final exporter = OtlpHttpLogExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/logs'),
        httpClient: buildClient(200),
        headers: const {'Content-Type': 'text/plain'},
      );

      await exporter.export(
        [LogRecord(body: 'x')],
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
      final exporter = OtlpHttpLogExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/logs'),
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
      final exporter = OtlpHttpLogExporter(
        endpoint: Uri.parse('https://collector.example.com/v1/logs'),
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
