import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:flutter_otel_instrumentation_dio/flutter_otel_instrumentation_dio.dart';
import 'package:test/test.dart';

class _RecordingLogger extends Logger {
  final List<LogRecord> emitted = [];

  @override
  void emit(LogRecord record) => emitted.add(record);
}

class _ThrowingLogger extends Logger {
  @override
  void emit(LogRecord record) => throw StateError('boom: a misbehaving logger');
}

class _RecordingSpan implements Span {
  _RecordingSpan(this.name, this.spanContext, this.kind);

  @override
  final String name;

  @override
  final SpanContext spanContext;

  final SpanKind kind;
  final Map<String, Object?> attributes = {};
  final List<SpanEvent> events = [];
  StatusCode? statusCode;
  String? statusDescription;
  Object? recordedException;
  bool ended = false;

  @override
  bool get isRecording => !ended;

  @override
  void setAttribute(String key, Object? value) => attributes[key] = value;

  @override
  void setAttributes(Map<String, Object?> attributes) =>
      this.attributes.addAll(attributes);

  @override
  void addEvent(
    String name, {
    Map<String, Object?>? attributes,
    DateTime? timestamp,
  }) =>
      events.add(
        SpanEvent(
          name: name,
          timestamp: timestamp,
          attributes: attributes ?? const {},
        ),
      );

  @override
  void setStatus(StatusCode code, {String? description}) {
    statusCode = code;
    statusDescription = description;
  }

  @override
  void recordException(
    Object exception, {
    StackTrace? stackTrace,
    Map<String, Object?>? attributes,
  }) =>
      recordedException = exception;

  @override
  void end([DateTime? endTime]) => ended = true;
}

/// A [Tracer] test double that records every span it starts, so tests can
/// assert on kind/attributes/propagation without a real SDK pipeline.
class _RecordingTracer implements Tracer {
  final List<_RecordingSpan> startedSpans = [];
  int _counter = 0;

  @override
  String get name => 'test-tracer';

  @override
  Span startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    SpanContext? parentContext,
  }) {
    _counter++;
    final span = _RecordingSpan(
      name,
      SpanContext(
        traceId: 'a' * 32,
        spanId: _counter.toRadixString(16).padLeft(16, '0'),
      ),
      kind,
    );
    if (attributes != null) span.setAttributes(attributes);
    startedSpans.add(span);
    return span;
  }

  @override
  Future<T> startActiveSpan<T>(
    String name,
    Future<T> Function(Span span) body, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
  }) async {
    final span = startSpan(name, kind: kind, attributes: attributes);
    try {
      return await body(span);
    } finally {
      span.end();
    }
  }
}

class _ThrowingTracer implements Tracer {
  @override
  String get name => 'throwing-tracer';

  @override
  Span startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    SpanContext? parentContext,
  }) =>
      throw StateError('boom: a misbehaving tracer');

  @override
  Future<T> startActiveSpan<T>(
    String name,
    Future<T> Function(Span span) body, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
  }) =>
      throw StateError('boom: a misbehaving tracer');
}

void main() {
  late _RecordingLogger logger;
  late DateTime now;

  setUp(() {
    logger = _RecordingLogger();
    now = DateTime(2026, 1, 1, 12, 0, 0);
  });

  DioOTelInterceptor buildInterceptor({Duration advanceBy = Duration.zero}) {
    var current = now;
    return DioOTelInterceptor(
      logger,
      clock: () {
        current = current.add(advanceBy);
        return current;
      },
    );
  }

  RequestOptions buildRequestOptions() => RequestOptions(
        path: '/widgets',
        baseUrl: 'https://api.example.com',
        method: 'GET',
      );

  group('DioOTelInterceptor.onRequest', () {
    test('emits a debug record with method/url and forwards the request',
        () async {
      final interceptor = buildInterceptor();
      final options = buildRequestOptions();
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(logger.emitted, hasLength(1));
      final record = logger.emitted.single;
      expect(record.severity, LogSeverity.debug);
      expect(record.attributes['http.method'], 'GET');
      expect(record.attributes['http.url'], options.uri.toString());

      expect(handler.isCompleted, isTrue);
    });

    test('stamps a start time on the request for later duration calculation',
        () {
      final interceptor = buildInterceptor();
      final options = buildRequestOptions();
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(options.extra['flutter_otel.start_time'], isA<DateTime>());
    });

    test(
        'strips user-info and query parameters from the logged URL by '
        'default', () {
      final interceptor = buildInterceptor();
      final options = RequestOptions(
        path: '/widgets',
        baseUrl: 'https://user:pass@api.example.com',
        method: 'GET',
        queryParameters: {'access_token': 'super-secret'},
      );
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      final record = logger.emitted.single;
      final loggedUrl = record.attributes['http.url'] as String;
      expect(loggedUrl, isNot(contains('super-secret')));
      expect(loggedUrl, isNot(contains('user:pass')));
      expect(loggedUrl, isNot(contains('access_token')));
      expect(loggedUrl, 'https://api.example.com/widgets');
    });

    test('preserves user-info and query parameters when opted in', () {
      var current = now;
      final interceptor = DioOTelInterceptor(
        logger,
        clock: () => current,
        includeQueryParameters: true,
      );
      final options = RequestOptions(
        path: '/widgets',
        baseUrl: 'https://user:pass@api.example.com',
        method: 'GET',
        queryParameters: {'access_token': 'super-secret'},
      );
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      final record = logger.emitted.single;
      final loggedUrl = record.attributes['http.url'] as String;
      expect(loggedUrl, contains('super-secret'));
      expect(loggedUrl, contains('access_token'));
    });

    test('still forwards the request when the injected Logger throws', () {
      final interceptor = DioOTelInterceptor(_ThrowingLogger());
      final options = buildRequestOptions();
      final handler = RequestInterceptorHandler();

      expect(() => interceptor.onRequest(options, handler), returnsNormally);
      expect(handler.isCompleted, isTrue);
    });
  });

  group('DioOTelInterceptor.onResponse', () {
    test(
        'emits an info record with status code and duration, and forwards '
        'the response', () async {
      final interceptor =
          buildInterceptor(advanceBy: const Duration(milliseconds: 42));
      final options = buildRequestOptions();
      final requestHandler = RequestInterceptorHandler();
      interceptor.onRequest(options, requestHandler);

      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
      );
      final responseHandler = ResponseInterceptorHandler();
      interceptor.onResponse(response, responseHandler);

      final record = logger.emitted.last;
      expect(record.severity, LogSeverity.info);
      expect(record.attributes['http.method'], 'GET');
      expect(record.attributes['http.status_code'], 200);
      expect(record.attributes['duration_ms'], 42);

      expect(responseHandler.isCompleted, isTrue);
    });

    test('omits duration_ms if the request never went through onRequest',
        () async {
      final interceptor = buildInterceptor();
      final options = buildRequestOptions();
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 204,
      );
      final handler = ResponseInterceptorHandler();

      interceptor.onResponse(response, handler);

      final record = logger.emitted.single;
      expect(record.attributes.containsKey('duration_ms'), isFalse);
    });

    test('still forwards the response when the injected Logger throws', () {
      final interceptor = DioOTelInterceptor(_ThrowingLogger());
      final options = buildRequestOptions();
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
      );
      final handler = ResponseInterceptorHandler();

      expect(
        () => interceptor.onResponse(response, handler),
        returnsNormally,
      );
      expect(handler.isCompleted, isTrue);
    });
  });

  // onError is driven through a real Dio instance with a fake adapter
  // (rather than calling interceptor.onError directly) because Dio's error
  // handler completes an internal Completer with an error; unless something
  // downstream actually awaits it, the test zone reports it as an unhandled
  // async error. Running the real pipeline gives that completer its normal
  // consumer (dio.get()'s returned Future) instead of leaving it dangling.
  group('DioOTelInterceptor.onError', () {
    test(
        'emits an error record and forwards the error for a connection '
        'failure', () async {
      final interceptor = buildInterceptor();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..interceptors.add(interceptor)
        ..httpClientAdapter =
            _FakeAdapter(throwError: const SocketExceptionStub());

      await expectLater(
        dio.get<void>('/widgets'),
        throwsA(isA<DioException>()),
      );

      final record = logger.emitted.last;
      expect(record.severity, LogSeverity.error);
      expect(record.attributes['http.method'], 'GET');
      expect(record.attributes.containsKey('error.type'), isTrue);
      expect(
        record.attributes['exception.type'],
        contains('SocketExceptionStub'),
      );
      expect(record.attributes['duration_ms'], isA<int>());
    });

    test('includes the response status code when the error carries one',
        () async {
      final interceptor = buildInterceptor();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..interceptors.add(interceptor)
        ..httpClientAdapter = _FakeAdapter(statusCode: 503);

      await expectLater(
        dio.get<void>('/widgets'),
        throwsA(isA<DioException>()),
      );

      final errorRecord =
          logger.emitted.firstWhere((r) => r.severity == LogSeverity.error);
      expect(errorRecord.attributes['http.status_code'], 503);
    });

    test(
        'strips user-info and query parameters from the logged URL by '
        'default', () async {
      final interceptor = buildInterceptor();
      final dio = Dio(BaseOptions(baseUrl: 'https://user:pass@api.example.com'))
        ..interceptors.add(interceptor)
        ..httpClientAdapter = _FakeAdapter(statusCode: 503);

      await expectLater(
        dio.get<void>('/widgets', queryParameters: {
          'access_token': 'super-secret',
        }),
        throwsA(isA<DioException>()),
      );

      final errorRecord =
          logger.emitted.firstWhere((r) => r.severity == LogSeverity.error);
      final loggedUrl = errorRecord.attributes['http.url'] as String;
      expect(loggedUrl, isNot(contains('super-secret')));
      expect(loggedUrl, isNot(contains('user:pass')));
    });

    test('still forwards the error when the injected Logger throws', () async {
      final interceptor = DioOTelInterceptor(_ThrowingLogger());
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..interceptors.add(interceptor)
        ..httpClientAdapter =
            _FakeAdapter(throwError: const SocketExceptionStub());

      await expectLater(
        dio.get<void>('/widgets'),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('DioOTelInterceptor with a Tracer', () {
    test('onRequest without a tracer never injects a traceparent header', () {
      final interceptor = buildInterceptor();
      final options = buildRequestOptions();
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(options.headers.containsKey('traceparent'), isFalse);
    });

    test(
        'onRequest starts a CLIENT span and injects a matching traceparent '
        'header', () {
      final tracer = _RecordingTracer();
      final interceptor = DioOTelInterceptor(logger, tracer: tracer);
      final options = buildRequestOptions();
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(tracer.startedSpans, hasLength(1));
      final span = tracer.startedSpans.single;
      expect(span.kind, SpanKind.client);
      expect(span.attributes['http.method'], 'GET');
      expect(span.attributes['http.url'], options.uri.toString());

      expect(
        options.headers['traceparent'],
        formatTraceparent(span.spanContext),
      );
      expect(handler.isCompleted, isTrue);
    });

    test('onResponse ends the span with an ok status and the status code', () {
      final tracer = _RecordingTracer();
      final interceptor = DioOTelInterceptor(logger, tracer: tracer);
      final options = buildRequestOptions();
      interceptor.onRequest(options, RequestInterceptorHandler());

      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
      );
      final handler = ResponseInterceptorHandler();
      interceptor.onResponse(response, handler);

      final span = tracer.startedSpans.single;
      expect(span.ended, isTrue);
      expect(span.statusCode, StatusCode.ok);
      expect(span.attributes['http.status_code'], 200);
      expect(handler.isCompleted, isTrue);
    });

    test(
        'onError ends the span with an error status and records the '
        'exception', () async {
      final tracer = _RecordingTracer();
      final interceptor = DioOTelInterceptor(logger, tracer: tracer);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..interceptors.add(interceptor)
        ..httpClientAdapter =
            _FakeAdapter(throwError: const SocketExceptionStub());

      await expectLater(
        dio.get<void>('/widgets'),
        throwsA(isA<DioException>()),
      );

      final span = tracer.startedSpans.single;
      expect(span.ended, isTrue);
      expect(span.statusCode, StatusCode.error);
      expect(span.recordedException, isNotNull);
    });

    test('still forwards the request when the injected Tracer throws', () {
      final interceptor = DioOTelInterceptor(logger, tracer: _ThrowingTracer());
      final options = buildRequestOptions();
      final handler = RequestInterceptorHandler();

      expect(() => interceptor.onRequest(options, handler), returnsNormally);
      expect(handler.isCompleted, isTrue);
      expect(logger.emitted, hasLength(1)); // the log call still went through
    });

    test('still forwards the response when the injected Tracer throws', () {
      // The span itself throws on every mutation, but onRequest already
      // stashed it in extra — exercise onResponse's retrieval + mutation
      // path, not just onRequest's creation path.
      final interceptor = DioOTelInterceptor(logger, tracer: _ThrowingTracer());
      final options = buildRequestOptions();
      // _ThrowingTracer.startSpan throws, so onRequest's _safeTrace catches
      // it and no span ever lands in extra; onResponse must still tolerate
      // that (no span to retrieve) without throwing.
      interceptor.onRequest(options, RequestInterceptorHandler());
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
      );
      final handler = ResponseInterceptorHandler();

      expect(
        () => interceptor.onResponse(response, handler),
        returnsNormally,
      );
      expect(handler.isCompleted, isTrue);
    });

    test('still forwards the error when the injected Tracer throws', () async {
      final interceptor = DioOTelInterceptor(logger, tracer: _ThrowingTracer());
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..interceptors.add(interceptor)
        ..httpClientAdapter =
            _FakeAdapter(throwError: const SocketExceptionStub());

      await expectLater(
        dio.get<void>('/widgets'),
        throwsA(isA<DioException>()),
      );
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'SocketExceptionStub';
}

/// A minimal [HttpClientAdapter] test double: either throws [throwError] or
/// responds with an empty JSON body at [statusCode].
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.statusCode, this.throwError});

  final int? statusCode;
  final Object? throwError;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final error = throwError;
    if (error != null) {
      throw error;
    }
    return ResponseBody.fromString(
      '{}',
      statusCode!,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
