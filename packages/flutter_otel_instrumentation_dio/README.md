# flutter_otel_instrumentation_dio

[Dio](https://pub.dev/packages/dio) HTTP client instrumentation for
flutter_otel: a `DioOTelInterceptor` that emits a log record per
request/response/error via an injected `Logger`.

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
    behavior).

## Install

```yaml
dependencies:
  flutter_otel_instrumentation_dio:
    git:
      url: https://github.com/cedricziel/flutter-otel
      path: packages/flutter_otel_instrumentation_dio
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
