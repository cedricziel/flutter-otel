import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:http/http.dart' as http;

/// Wraps an [http.Client] so every request sent through it opens a
/// client-kind [Span], carries a `traceparent` header derived from that span,
/// and closes the span with the response's outcome.
///
/// [tracerProvider] is called per request rather than once, so a tracer that
/// is replaced after construction (for example by re-initializing the SDK) is
/// picked up immediately.
///
/// [routeTemplate] maps a request path to the route used in the span name
/// (`GET /notes/:id`), keeping identifiers out of span-name cardinality. The
/// raw path is still recorded as `url.path`.
///
/// With [captureHeaders] (the default) request and response headers are
/// recorded as `http.request.header.<key>` / `http.response.header.<key>`
/// attributes per the OpenTelemetry HTTP semantic conventions, with values of
/// credential-bearing headers replaced by [redactedHttpHeaderValue] (see
/// [isSensitiveHttpHeader]).
class TracingHttpClient extends http.BaseClient {
  TracingHttpClient(
    this._inner, {
    required Tracer Function() tracerProvider,
    String Function(String path)? routeTemplate,
    this.captureHeaders = true,
  })  : _tracerProvider = tracerProvider,
        _routeTemplate = routeTemplate ?? _identity;

  final http.Client _inner;
  final Tracer Function() _tracerProvider;
  final String Function(String path) _routeTemplate;
  final bool captureHeaders;

  static String _identity(String path) => path;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final span = _tracerProvider().startSpan(
      '${request.method} ${_routeTemplate(request.url.path)}',
      kind: SpanKind.client,
      attributes: {
        'http.request.method': request.method,
        'url.path': request.url.path,
      },
    );
    request.headers['traceparent'] = formatTraceparent(span.spanContext);
    if (captureHeaders) {
      span.setAttributes(httpRequestHeaderAttributes(request.headers));
    }
    try {
      final response = await _inner.send(request);
      span.setAttribute('http.response.status_code', response.statusCode);
      if (captureHeaders) {
        span.setAttributes(httpResponseHeaderAttributes(response.headers));
      }
      if (response.statusCode >= 500) {
        span.setStatus(StatusCode.error);
      }
      return response;
    } catch (e, stackTrace) {
      span
        ..recordException(e, stackTrace: stackTrace)
        ..setStatus(StatusCode.error, description: e.toString());
      rethrow;
    } finally {
      span.end();
    }
  }

  @override
  void close() => _inner.close();
}
