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
