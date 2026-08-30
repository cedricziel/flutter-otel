import 'package:dio/dio.dart';
import 'package:flutter_otel_api/flutter_otel_api.dart';

/// A Dio [Interceptor] that emits a [LogRecord] (via an injected [Logger])
/// for every outgoing request, successful response, and error.
///
/// The app is responsible for obtaining the [Logger] (typically via
/// `OTelSdk.instance.getLogger(name: 'flutter_otel_instrumentation_dio')`)
/// and adding this interceptor to its [Dio] instance:
///
/// ```dart
/// dio.interceptors.add(DioOTelInterceptor(otel.getLogger()));
/// ```
///
/// This establishes the `flutter_otel_instrumentation_<target>` pattern:
/// future packages (navigation, go_router, ...) follow the same shape of
/// "take a [Logger], emit records with semantic-convention-ish attributes".
class DioOTelInterceptor extends Interceptor {
  DioOTelInterceptor(this._logger, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const String _startTimeKey = 'flutter_otel.start_time';

  final Logger _logger;
  final DateTime Function() _clock;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    options.extra[_startTimeKey] = _clock();
    _logger.debug(
      'HTTP request started',
      attributes: {
        'http.method': options.method,
        'http.url': options.uri.toString(),
      },
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final durationMs = _durationMsSince(response.requestOptions);
    _logger.info(
      'HTTP request completed',
      attributes: {
        'http.method': response.requestOptions.method,
        'http.url': response.requestOptions.uri.toString(),
        if (response.statusCode != null)
          'http.status_code': response.statusCode,
        if (durationMs != null) 'duration_ms': durationMs,
      },
    );
    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    final durationMs = _durationMsSince(err.requestOptions);
    _logger.error(
      'HTTP request failed',
      error: err.error ?? err,
      stackTrace: err.stackTrace,
      attributes: {
        'http.method': err.requestOptions.method,
        'http.url': err.requestOptions.uri.toString(),
        if (err.response?.statusCode != null)
          'http.status_code': err.response!.statusCode,
        if (durationMs != null) 'duration_ms': durationMs,
        'error.type': err.type.toString(),
      },
    );
    handler.next(err);
  }

  int? _durationMsSince(RequestOptions options) {
    final start = options.extra[_startTimeKey];
    if (start is DateTime) {
      return _clock().difference(start).inMilliseconds;
    }
    return null;
  }
}
