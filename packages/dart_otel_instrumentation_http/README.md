# dart_otel_instrumentation_http

[`package:http`](https://pub.dev/packages/http) client instrumentation for
dart_otel. `TracingHttpClient` wraps any `http.Client` and, per request:

- starts a `SpanKind.client` span named `<METHOD> <route>` with
  `http.method` / `http.target`, and `http.status_code` on completion (error
  status for 5xx or a thrown exception),
- injects a W3C `traceparent` header so the server joins the trace,
- captures request and response headers as `http.request.header.<key>` /
  `http.response.header.<key>` string-array attributes, following the
  OpenTelemetry HTTP semantic conventions (lowercase name, `-` → `_`).
  Values of credential-bearing headers (`Authorization`, `Cookie`,
  `Set-Cookie`, anything containing `token`, `secret`, `api-key`, ...) are
  replaced with `[REDACTED]`. Pass `captureHeaders: false` to turn capture off.

```dart
final client = TracingHttpClient(
  http.Client(),
  tracerProvider: () => otel.getTracer(),
  routeTemplate: (path) => path.replaceAll(RegExp(r'/notes/[^/]+'), '/notes/:id'),
);
```

Pure Dart. Depends on `dart_otel_api` and `http`.
