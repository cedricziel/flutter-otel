import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:flutter_otel_instrumentation_dio/flutter_otel_instrumentation_dio.dart';
import 'package:test/test.dart';

import 'support/recording_logger.dart';
import 'support/recording_tracer.dart';

const _host = 'secret-server.example.org';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._respond);

  final Future<ResponseBody> Function(RequestOptions options) _respond;
  final List<Map<String, dynamic>> requestHeaders = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requestHeaders.add(Map.of(options.headers));
    return _respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late RecordingTracer tracer;
  late RecordingLogger logger;

  Dio buildDio(
    Future<ResponseBody> Function(RequestOptions) respond, {
    Tracer? withTracer,
    Logger? withLogger,
    int? routeSegments,
  }) {
    final dio = Dio(BaseOptions(baseUrl: 'https://$_host'));
    dio.httpClientAdapter = _FakeAdapter(respond);
    dio.interceptors.add(
      DioOTelInterceptor.privacy(
        withLogger ?? logger,
        tracer: withTracer ?? tracer,
        routeSegments: routeSegments,
      ),
    );
    return dio;
  }

  setUp(() {
    tracer = RecordingTracer();
    logger = RecordingLogger();
  });

  test('records a client span with method, route and status', () async {
    final dio = buildDio((_) async => ResponseBody.fromString('{}', 200));

    await dio.get<dynamic>('/api/status');

    final span = tracer.spans.single;
    expect(span.name, 'HTTP GET');
    expect(span.kind, SpanKind.client);
    expect(span.attributes, {
      'http.method': 'GET',
      'http.route': '/api/status',
      'http.status_code': 200,
    });
    expect(span.status, StatusCode.ok);
    expect(span.ended, isTrue);
  });

  test('marks 4xx/5xx responses as errors and still ends the span', () async {
    final dio = buildDio((_) async => ResponseBody.fromString('', 500));

    await expectLater(dio.get<dynamic>('/api/x'), throwsA(isA<DioException>()));

    final span = tracer.spans.single;
    expect(span.attributes['http.status_code'], 500);
    expect(span.attributes['error.type'], 'badResponse');
    expect(span.status, StatusCode.error);
    expect(span.ended, isTrue);
  });

  test('keeps the query string out of the span route', () async {
    final dio = buildDio((_) async => ResponseBody.fromString('{}', 200));

    await dio.get<dynamic>('/api/x?token=hunter2');

    expect(tracer.spans.single.attributes['http.route'], '/api/x');
  });

  group('with routeSegments', () {
    test('keeps only the leading segments, so path parameters never leave',
        () async {
      final dio = buildDio(
        (_) async => ResponseBody.fromString('{}', 200),
        routeSegments: 2,
      );

      await dio.get<dynamic>('/api/sessions/20260918-secret/messages?x=1');

      expect(tracer.spans.single.attributes['http.route'], '/api/sessions');
      expect(logger.records.single.attributes['http.route'], '/api/sessions');
      expect(logger.records.single.body, 'HTTP GET /api/sessions 200');
    });

    test('leaves a path shorter than the limit as it is', () async {
      final dio = buildDio(
        (_) async => ResponseBody.fromString('{}', 200),
        routeSegments: 2,
      );

      await dio.get<dynamic>('/api/status');

      expect(tracer.spans.single.attributes['http.route'], '/api/status');
    });

    test('still records no route for a network-path reference', () async {
      final dio = buildDio(
        (_) async => ResponseBody.fromString('{}', 200),
        routeSegments: 2,
      );

      await dio.get<dynamic>('//$_host/api/status');

      expect(tracer.spans.single.attributes, isNot(contains('http.route')));
    });
  });

  test('never exports the server host or exception details', () async {
    final dio = buildDio(
      (options) async => throw DioException.connectionError(
        requestOptions: options,
        reason: 'Failed host lookup: $_host',
      ),
    );

    await expectLater(dio.get<dynamic>('/api/x'), throwsA(isA<DioException>()));

    final span = tracer.spans.single;
    expect(span.attributes['error.type'], 'connectionError');
    expect(span.statusDescription, isNull);
    expect(span.events, isEmpty);
    expect(span.attributes.values.join(' '), isNot(contains(_host)));
  });

  test(
    'leaves out the route when the request path is an absolute URL',
    () async {
      final dio = buildDio((_) async => ResponseBody.fromString('', 200));

      await dio.get<dynamic>('https://$_host/auth/native/refresh');

      final span = tracer.spans.single;
      expect(span.attributes.containsKey('http.route'), isFalse);
      expect(span.attributes.values.join(' '), isNot(contains(_host)));
    },
  );

  test('leaves out the route for a network-path reference', () async {
    final dio = buildDio((_) async => ResponseBody.fromString('', 200));

    await dio.get<dynamic>('//$_host/api/status');

    final span = tracer.spans.single;
    expect(span.attributes.containsKey('http.route'), isFalse);
    expect(span.attributes.values.join(' '), isNot(contains(_host)));
    final record = logger.records.single;
    expect('${record.body} ${record.attributes}', isNot(contains(_host)));
  });

  test('does not add a traceparent header to requests', () async {
    final adapter = _FakeAdapter((_) async => ResponseBody.fromString('', 200));
    final dio = Dio(BaseOptions(baseUrl: 'https://$_host'))
      ..httpClientAdapter = adapter
      ..interceptors.add(DioOTelInterceptor.privacy(logger, tracer: tracer));

    await dio.get<dynamic>('/api/status');

    expect(
      adapter.requestHeaders.single.keys.map((k) => k.toLowerCase()),
      isNot(contains('traceparent')),
    );
  });

  test('a failing tracer never breaks the request', () async {
    final dio = buildDio(
      (_) async => ResponseBody.fromString('{}', 200),
      withTracer: ThrowingTracer(),
    );

    final response = await dio.get<dynamic>('/api/status');

    expect(response.statusCode, 200);
  });

  group('logs', () {
    test(
      'records an info log with method, route, status and duration',
      () async {
        final dio = buildDio((_) async => ResponseBody.fromString('{}', 200));

        await dio.get<dynamic>('/api/status');

        final record = logger.records.single;
        expect(record.severity, LogSeverity.info);
        expect(record.body, 'HTTP GET /api/status 200');
        expect(record.attributes['http.method'], 'GET');
        expect(record.attributes['http.route'], '/api/status');
        expect(record.attributes['http.status_code'], 200);
        expect(record.attributes['http.duration_ms'], isA<int>());
        expect(record.attributes.containsKey('error.type'), isFalse);
      },
    );

    test('links the log to the request span', () async {
      final dio = buildDio((_) async => ResponseBody.fromString('{}', 200));

      await dio.get<dynamic>('/api/status');

      final context = tracer.spans.single.spanContext;
      expect(logger.records.single.traceId, context.traceId);
      expect(logger.records.single.spanId, context.spanId);
    });

    test('logs a non-2xx response as an error with its status', () async {
      final dio = buildDio((_) async => ResponseBody.fromString('', 500));

      await expectLater(
        dio.get<dynamic>('/api/x'),
        throwsA(isA<DioException>()),
      );

      final record = logger.records.single;
      expect(record.severity, LogSeverity.error);
      expect(record.body, 'HTTP GET /api/x 500');
      expect(record.attributes['http.status_code'], 500);
      expect(record.attributes['error.type'], 'badResponse');
    });

    test('logs a failure without a response as an error', () async {
      final dio = buildDio(
        (options) async => throw DioException.connectionError(
          requestOptions: options,
          reason: 'Failed host lookup: $_host',
        ),
      );

      await expectLater(
        dio.get<dynamic>('/api/x'),
        throwsA(isA<DioException>()),
      );

      final record = logger.records.single;
      expect(record.severity, LogSeverity.error);
      expect(record.body, 'HTTP GET /api/x connectionError');
      expect(record.attributes['error.type'], 'connectionError');
      expect(record.attributes.containsKey('http.status_code'), isFalse);
    });

    test('never logs the host, query string or request data', () async {
      final dio = buildDio(
        (options) async => throw DioException.connectionError(
          requestOptions: options,
          reason: 'Failed host lookup: $_host',
        ),
      );

      await expectLater(
        dio.post<dynamic>(
          '/api/x?token=hunter2#frag',
          data: {'message': 'my secret prompt'},
          options: Options(headers: {'Authorization': 'Bearer hunter2'}),
        ),
        throwsA(isA<DioException>()),
      );

      final record = logger.records.single;
      final everything = '${record.body} ${record.attributes}';
      expect(record.attributes['http.route'], '/api/x');
      for (final secret in [_host, 'hunter2', 'frag', 'secret prompt']) {
        expect(everything, isNot(contains(secret)));
      }
    });

    test(
      'leaves out the route when the request path is an absolute URL',
      () async {
        final dio = buildDio((_) async => ResponseBody.fromString('', 200));

        await dio.get<dynamic>('https://$_host/auth/native/refresh?code=abc');

        final record = logger.records.single;
        expect(record.body, 'HTTP GET 200');
        expect(record.attributes.containsKey('http.route'), isFalse);
        expect('${record.body} ${record.attributes}', isNot(contains(_host)));
      },
    );

    test('a failing logger never breaks the request or the span', () async {
      final dio = buildDio(
        (_) async => ResponseBody.fromString('{}', 200),
        withLogger: ThrowingLogger(),
      );

      final response = await dio.get<dynamic>('/api/status');

      expect(response.statusCode, 200);
      expect(tracer.spans.single.ended, isTrue);
    });

    test('logs without trace ids when no tracer is supplied', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://$_host'))
        ..httpClientAdapter = _FakeAdapter(
          (_) async => ResponseBody.fromString('{}', 200),
        )
        ..interceptors.add(DioOTelInterceptor.privacy(logger));

      await dio.get<dynamic>('/api/status');

      final record = logger.records.single;
      expect(record.body, 'HTTP GET /api/status 200');
      expect(record.traceId, isNull);
      expect(record.spanId, isNull);
    });

    test('a failing tracer still logs the request', () async {
      final dio = buildDio(
        (_) async => ResponseBody.fromString('{}', 200),
        withTracer: ThrowingTracer(),
      );

      await dio.get<dynamic>('/api/status');

      expect(logger.records.single.body, 'HTTP GET /api/status 200');
      expect(logger.records.single.traceId, isNull);
    });
  });
}
