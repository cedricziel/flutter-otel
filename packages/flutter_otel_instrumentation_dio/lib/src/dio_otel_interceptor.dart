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
  DioOTelInterceptor(
    this._logger, {
    DateTime Function()? clock,
    this.includeQueryParameters = false,
  }) : _clock = clock ?? DateTime.now;

  static const String _startTimeKey = 'flutter_otel.start_time';

  final Logger _logger;
  final DateTime Function() _clock;

  /// Whether to include user-info and query parameters when logging request
  /// URLs.
  ///
  /// Defaults to `false` because query strings (and less commonly user-info)
  /// frequently carry credentials or access tokens (e.g.
  /// `?access_token=...`), which must not end up in logs/telemetry by
  /// default. Set this to `true` only when the app is certain its URLs never
  /// carry sensitive data and the query parameters are useful for debugging.
  final bool includeQueryParameters;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    options.extra[_startTimeKey] = _clock();
    _safeLog(() {
      _logger.debug(
        'HTTP request started',
        attributes: {
          'http.method': options.method,
          'http.url': _sanitizeUrl(options.uri),
        },
      );
    });
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final durationMs = _durationMsSince(response.requestOptions);
    _safeLog(() {
      _logger.info(
        'HTTP request completed',
        attributes: {
          'http.method': response.requestOptions.method,
          'http.url': _sanitizeUrl(response.requestOptions.uri),
          if (response.statusCode != null)
            'http.status_code': response.statusCode,
          if (durationMs != null) 'duration_ms': durationMs,
        },
      );
    });
    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    final durationMs = _durationMsSince(err.requestOptions);
    _safeLog(() {
      _logger.error(
        'HTTP request failed',
        error: err.error ?? err,
        stackTrace: err.stackTrace,
        attributes: {
          'http.method': err.requestOptions.method,
          'http.url': _sanitizeUrl(err.requestOptions.uri),
          if (err.response?.statusCode != null)
            'http.status_code': err.response!.statusCode,
          if (durationMs != null) 'duration_ms': durationMs,
          'error.type': err.type.toString(),
        },
      );
    });
    handler.next(err);
  }

  int? _durationMsSince(RequestOptions options) {
    final start = options.extra[_startTimeKey];
    if (start is DateTime) {
      return _clock().difference(start).inMilliseconds;
    }
    return null;
  }

  /// Strips user-info and (unless [includeQueryParameters] is set) the query
  /// string from [uri] before it is attached to a log record, so that
  /// credentials or access tokens carried in either don't end up in logs or
  /// exported telemetry.
  String _sanitizeUrl(Uri uri) {
    final sanitized = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      query: includeQueryParameters && uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    );
    return sanitized.toString();
  }

  /// Runs [log], swallowing any exception it throws.
  ///
  /// A misbehaving injected [Logger] must never be able to prevent the Dio
  /// handler chain (`handler.next`/`resolve`/`reject`) from being invoked.
  void _safeLog(void Function() log) {
    try {
      log();
    } catch (_) {
      // Intentionally ignored: a throwing Logger must not break networking.
    }
  }
}
