# flutter_otel_instrumentation_dio

[Dio](https://pub.dev/packages/dio) HTTP client instrumentation for
flutter_otel: a `DioOTelInterceptor` that emits a log record per
request/response/error via an injected `Logger`, and — when a `Tracer` is
also supplied — starts a real CLIENT span per request and propagates it to
the server via a W3C `traceparent` header.

This is the first of the `flutter_otel_instrumentation_<target>` family —
the pattern future instrumentation packages (navigation, `go_router`, ...)
will follow: take a `Logger`, emit records with semantic-convention-ish
attributes, stay out of the way otherwise.

Pure Dart — no Flutter dependency (Dio itself has none either) — so
`dart analyze` / `dart test` are used for it rather than the `flutter`
equivalents.

## Position in the dependency graph

```
flutter_otel_api ──> flutter_otel_instrumentation_dio
```

Depends on `flutter_otel_api` and `dio`. Nothing else in the workspace
depends on it — apps that use Dio add it directly alongside `flutter_otel`.

## What's in here

- `DioOTelInterceptor` — a Dio `Interceptor` that:
  - emits a `debug` record on `onRequest` (`http.method`, `http.url`) and
    stamps a start time for later duration calculation,
  - emits an `info` record on `onResponse` (adds `http.status_code` and
    `duration_ms`),
  - emits an `error` record on `onError` (adds `error.type`, and
    `http.status_code` when the failed response carries one, plus the
    usual `exception.type`/`exception.message` from the base `Logger.error`
    behavior),
  - when constructed with `tracer:`, additionally starts a `SpanKind.client`
    span per request on `onRequest` (with `http.method`/`http.url`
    attributes) and injects it as a `traceparent` header on the outgoing
    request, joining it into whatever trace/span is active when the request
    is made; `onResponse` sets `http.status_code` and an `ok` status and
    ends the span, and `onError` records the exception, sets an `error`
    status, and ends the span.

  Both the logging and tracing paths are independently exception-safe: a
  throwing `Logger` or `Tracer`/`Span` can never prevent the Dio handler
  chain (`handler.next`/`resolve`/`reject`) from running.

## Privacy mode

The default constructor records the request URL (minus user-info and, unless
`includeQueryParameters` is set, the query string), the exception on failure,
and injects a `traceparent` header. That is unsuitable when the server
address is not yours to publish, for example when the user typed it into the
app. `DioOTelInterceptor.privacy` records only what cannot identify the
server:

```dart
dio.interceptors.add(
  DioOTelInterceptor.privacy(
    OTelSdk.instance.getLogger(name: 'flutter_otel_instrumentation_dio'),
    tracer: OTelSdk.instance.getTracer(name: 'flutter_otel_instrumentation_dio'),
  ),
);
```

- One CLIENT span per request, named `HTTP <METHOD>`, with `http.method`,
  `http.route` (when known), `http.status_code` and `error.type`. Its status
  is `error` for a status of 400 or above or for a `DioException`, `ok`
  otherwise.
- One log record per finished request, with body
  `HTTP <METHOD> <route> <status or error type>` (the route is left out when
  unknown), severity `error` for a status of 400 or above or for a
  `DioException` and `info` otherwise (the same rule as the span status), and
  the attributes `http.method`, `http.route`, `http.status_code`,
  `http.duration_ms` and `error.type`, plus the span's trace and span ids.
- `http.route` is the first two segments of the request path when it is
  relative (starts with `/`), without query or fragment, so
  `/api/sessions/<id>/messages` is recorded as `/api/sessions` and path
  parameters such as ids and names are not exported. Pass `routeSegments` to
  keep a different number. For an absolute request path, or one starting with
  `//`, no route is recorded, so a `baseUrl` never leaks either.
- No `traceparent` header is added, so no trace context reaches the server.
- No exception message or stack trace is recorded, because Dio puts the host
  in them. `error.type` is the `DioExceptionType` name, for example
  `connectionError`.
- A failing `Logger` or `Tracer` never breaks the request, as in the default
  mode.

## Install

```yaml
dependencies:
  flutter_otel: # for OTelSdk, used in the example below
    git:
      url: https://github.com/cedricziel/flutter-otel
      ref: main # pin to a commit or tag in real usage
      path: packages/flutter_otel
  flutter_otel_instrumentation_dio:
    git:
      url: https://github.com/cedricziel/flutter-otel
      ref: main
      path: packages/flutter_otel_instrumentation_dio

# These transitive workspace packages are unpublished, so pub can't resolve
# them on its own — pin them here too, at the same ref, or pub get will fail.
dependency_overrides:
  flutter_otel_api:
    git:
      url: https://github.com/cedricziel/flutter-otel
      ref: main
      path: packages/flutter_otel_api
  flutter_otel_sdk:
    git:
      url: https://github.com/cedricziel/flutter-otel
      ref: main
      path: packages/flutter_otel_sdk
  flutter_otel_exporter_otlp_http:
    git:
      url: https://github.com/cedricziel/flutter-otel
      ref: main
      path: packages/flutter_otel_exporter_otlp_http
```

## Usage example

```dart
import 'package:dio/dio.dart';
import 'package:flutter_otel/flutter_otel.dart'; // for OTelSdk
import 'package:flutter_otel_instrumentation_dio/flutter_otel_instrumentation_dio.dart';

void wireUpDio(Dio dio) {
  dio.interceptors.add(
    DioOTelInterceptor(
      OTelSdk.instance.getLogger(name: 'flutter_otel_instrumentation_dio'),
      // Optional: also emit a CLIENT span per request and propagate the
      // active trace to the server via a `traceparent` header. Omit this
      // to keep the log-only behavior from before tracing existed.
      tracer: OTelSdk.instance.getTracer(name: 'flutter_otel_instrumentation_dio'),
    ),
  );
}
```

## Testing

```bash
cd packages/flutter_otel_instrumentation_dio
dart pub get   # or rely on the workspace root's `flutter pub get`
dart analyze
dart test
```
