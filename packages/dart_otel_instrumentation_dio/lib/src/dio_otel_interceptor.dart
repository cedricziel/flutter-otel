import 'package:dio/dio.dart';
import 'package:dart_otel_api/dart_otel_api.dart';

/// A Dio [Interceptor] that emits a [LogRecord] (via an injected [Logger])
/// for every outgoing request, successful response, and error, and
/// (optionally, when a [Tracer] is supplied) produces a real CLIENT [Span]
/// per request with W3C `traceparent` propagation to the server.
///
/// The app is responsible for obtaining the [Logger] (typically via
/// `OTelSdk.instance.getLogger(name: 'dart_otel_instrumentation_dio')`)
/// and adding this interceptor to its [Dio] instance:
///
/// ```dart
/// dio.interceptors.add(DioOTelInterceptor(otel.getLogger()));
/// ```
///
/// Passing a [Tracer] as well additionally starts a span per request and
/// injects it as a `traceparent` header, joining this request into
/// whatever trace/span is active when the request is made:
///
/// ```dart
/// dio.interceptors.add(
///   DioOTelInterceptor(otel.getLogger(), tracer: otel.getTracer()),
/// );
/// ```
///
/// The default constructor records request URLs and injects `traceparent`.
/// Apps that must not export the server address, for example because the
/// user typed it in, use [DioOTelInterceptor.privacy] instead.
///
/// This establishes the `dart_otel_instrumentation_<target>` pattern:
/// future packages (navigation, go_router, ...) follow the same shape of
/// "take a [Logger] (and optionally a [Tracer]), emit records/spans with
/// semantic-convention-ish attributes".
class DioOTelInterceptor extends Interceptor {
  DioOTelInterceptor(
    this._logger, {
    Tracer? tracer,
    DateTime Function()? clock,
    this.includeQueryParameters = false,
  })  : _privacy = false,
        routeSegments = 2,
        _tracer = tracer,
        _clock = clock ?? DateTime.now,
        _spanKey = 'flutter_otel.span.${_instanceCounter++}';

  /// Creates an interceptor for apps whose server address is not the app's
  /// own to publish, for example one the user typed in.
  ///
  /// Nothing that could identify the server or its traffic is recorded: no
  /// URL, host, user-info or query string, no exception message or stack
  /// trace, and no `traceparent` header is added to the request. What is
  /// recorded is the method, the status code, the [DioException] type name
  /// as `error.type`, the duration and, for relative request paths such as
  /// `/api/status`, the first [routeSegments] path segments as `http.route`
  /// (without query or fragment). Later segments are usually identifiers, so
  /// `/api/sessions/<id>/messages` is recorded as `/api/sessions`. For an
  /// absolute request path no route is recorded at all.
  ///
  /// Each request produces one log record when it finishes, and, when a
  /// [tracer] is supplied, one CLIENT span named `HTTP <METHOD>`. Both carry
  /// the same attributes, and the record is linked to the span by trace and
  /// span id. Like the default mode this never lets a failing [Logger] or
  /// [Tracer] break the request.
  DioOTelInterceptor.privacy(
    this._logger, {
    Tracer? tracer,
    DateTime Function()? clock,
    this.routeSegments = 2,
  })  : assert(routeSegments >= 1, 'routeSegments must be at least 1'),
        _privacy = true,
        includeQueryParameters = false,
        _tracer = tracer,
        _clock = clock ?? DateTime.now,
        _spanKey = 'flutter_otel.span.${_instanceCounter++}';

  static const String _startTimeKey = 'flutter_otel.start_time';
  static final RegExp _routeEnd = RegExp('[?#]');

  /// Monotonically increasing counter used to derive a unique [_spanKey]
  /// per instance ([RequestOptions.extra] keys must be [String]s, so a
  /// bare identity-based [Object] key can't be used directly).
  static int _instanceCounter = 0;

  /// Instance-specific key used to stash the in-flight span in
  /// [RequestOptions.extra]. Must not be a shared static/const key: if two
  /// [DioOTelInterceptor] instances are attached to the same [Dio] client,
  /// a shared key would let the second interceptor's span overwrite the
  /// first's in `extra`, so the first span would never be retrieved,
  /// `end()`'d, or exported.
  final String _spanKey;

  final bool _privacy;

  /// How many leading path segments [DioOTelInterceptor.privacy] keeps as
  /// `http.route`. Not used by the default constructor, which records the
  /// full URL.
  final int routeSegments;
  final Logger _logger;
  final Tracer? _tracer;
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
    if (_privacy) {
      _startPrivate(options);
      handler.next(options);
      return;
    }
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
    _safeTrace(() {
      final tracer = _tracer;
      if (tracer == null) return;
      final span = tracer.startSpan(
        'HTTP ${options.method}',
        kind: SpanKind.client,
        attributes: {
          'http.method': options.method,
          'http.url': _sanitizeUrl(options.uri),
        },
      );
      options.extra[_spanKey] = span;
      options.headers['traceparent'] = formatTraceparent(span.spanContext);
    });
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (_privacy) {
      _finishPrivate(response.requestOptions, status: response.statusCode);
      handler.next(response);
      return;
    }
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
    _safeTrace(() {
      final span = _takeSpan(response.requestOptions);
      if (span == null) return;
      final statusCode = response.statusCode;
      if (statusCode != null) {
        span.setAttribute('http.status_code', statusCode);
      }
      // A CLIENT span must be marked as an error for 4xx/5xx responses per
      // OTel HTTP semantic conventions, even when Dio's `validateStatus` is
      // configured to treat such a status as non-throwing and route it here
      // (rather than to onError).
      final isError =
          statusCode != null && statusCode >= 400 && statusCode < 600;
      span.setStatus(isError ? StatusCode.error : StatusCode.ok);
      span.end();
    });
    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    if (_privacy) {
      _finishPrivate(
        err.requestOptions,
        status: err.response?.statusCode,
        errorType: err.type.name,
      );
      handler.next(err);
      return;
    }
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
    _safeTrace(() {
      final span = _takeSpan(err.requestOptions);
      if (span == null) return;
      if (err.response?.statusCode != null) {
        span.setAttribute('http.status_code', err.response!.statusCode);
      }
      span.recordException(err.error ?? err, stackTrace: err.stackTrace);
      span.setStatus(StatusCode.error, description: err.message);
      span.end();
    });
    handler.next(err);
  }

  void _startPrivate(RequestOptions options) {
    options.extra[_startTimeKey] = _clock();
    _safeTrace(() {
      final route = _route(options.path);
      options.extra[_spanKey] = _tracer?.startSpan(
        'HTTP ${options.method}',
        kind: SpanKind.client,
        attributes: {
          'http.method': options.method,
          if (route != null) 'http.route': route,
        },
      );
    });
  }

  void _finishPrivate(
    RequestOptions options, {
    required int? status,
    String? errorType,
  }) {
    final durationMs = _durationMsSince(options);
    if (durationMs == null) return;
    // One rule for the span status and the log severity, so the two never
    // disagree. A 1xx, 2xx or 3xx status is not a failure, and neither is a
    // response whose status is unknown.
    final failed = errorType != null || (status != null && status >= 400);
    final span = _takeSpan(options);
    _safeTrace(() {
      if (span == null) return;
      if (status != null) span.setAttribute('http.status_code', status);
      if (errorType != null) span.setAttribute('error.type', errorType);
      span.setStatus(failed ? StatusCode.error : StatusCode.ok);
      span.end();
    });
    _safeLog(() {
      final route = _route(options.path);
      _logger.emit(
        LogRecord(
          body: [
            'HTTP ${options.method}',
            if (route != null) route,
            '${status ?? errorType}',
          ].join(' '),
          severity: failed ? LogSeverity.error : LogSeverity.info,
          attributes: {
            'http.method': options.method,
            if (route != null) 'http.route': route,
            if (status != null) 'http.status_code': status,
            'http.duration_ms': durationMs,
            if (errorType != null) 'error.type': errorType,
          },
          traceId: span?.spanContext.traceId,
          spanId: span?.spanContext.spanId,
        ),
      );
    });
  }

  /// The first [routeSegments] segments of a relative request path, without
  /// query or fragment.
  ///
  /// A leading `//` is a network-path reference that carries a host, so it
  /// yields no route.
  String? _route(String path) {
    if (!path.startsWith('/') || path.startsWith('//')) return null;
    final end = path.indexOf(_routeEnd);
    final segments = (end < 0 ? path : path.substring(0, end))
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .take(routeSegments);
    return '/${segments.join('/')}';
  }

  /// Removes and returns the [Span] stashed on [options] by [onRequest], if
  /// any (e.g. `null` when no [_tracer] was supplied, or this
  /// response/error is for a request this interceptor never saw).
  Span? _takeSpan(RequestOptions options) =>
      options.extra.remove(_spanKey) as Span?;

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

  /// Runs [trace], swallowing any exception it throws.
  ///
  /// A misbehaving injected [Tracer]/[Span] must never be able to prevent
  /// the Dio handler chain (`handler.next`/`resolve`/`reject`) from being
  /// invoked, exactly like [_safeLog] for the injected [Logger].
  void _safeTrace(void Function() trace) {
    try {
      trace();
    } catch (_) {
      // Intentionally ignored: a throwing Tracer/Span must not break
      // networking.
    }
  }
}
