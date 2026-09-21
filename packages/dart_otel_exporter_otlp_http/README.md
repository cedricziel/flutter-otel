# dart_otel_exporter_otlp_http

OTLP/HTTP log and span exporters using JSON encoding (the protobuf JSON
mapping) — no protobuf/binary codegen dependency.

Pure Dart — **no Flutter dependency** — so it works from non-Flutter Dart
targets (server, CLI, web) in addition to Flutter apps. The `http.Client` is
always injected, never constructed internally, so exporter behavior is
fully testable with `package:http/testing.dart`.

## Position in the dependency graph

```
dart_otel_api ──> dart_otel_exporter_otlp_http ──┬──> dart_otel_sdk
                                                        └──> flutter_otel (umbrella)
```

Depends on `dart_otel_api` and `http`. Depended on by `dart_otel_sdk`
(which wires it up inside `OTelSdk.initialize`) and the `flutter_otel`
umbrella package.

## What's in here

- `OtlpHttpLogExporter` — POSTs a batch of `LogRecord`s as OTLP/HTTP JSON to
  a resolved `/v1/logs` endpoint. Non-2xx responses and thrown exceptions
  both come back as a failed `ExportResult` rather than propagating — this
  exporter never throws out of `export()`.
- `OtlpHttpLogExporter.resolveLogsEndpoint` — resolves the effective logs
  endpoint per `OTEL_EXPORTER_OTLP_ENDPOINT` /
  `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` semantics: an explicit logs endpoint
  wins verbatim; otherwise `/v1/logs` is appended to a base endpoint.
- `OtlpHttpSpanExporter` — POSTs a batch of `SpanData` as OTLP/HTTP JSON to
  a resolved `/v1/traces` endpoint, mirroring `OtlpHttpLogExporter` in every
  respect (never throws, same header-injection pattern). `SpanKind` and
  `StatusCode` map 1:1 onto OTLP's numeric `SpanKind`/`StatusCode` enums.
- `OtlpHttpSpanExporter.resolveTracesEndpoint` — resolves the effective
  traces endpoint per `OTEL_EXPORTER_OTLP_ENDPOINT` /
  `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` semantics, mirroring
  `resolveLogsEndpoint`.

## Install

Usually pulled in transitively via the `flutter_otel` umbrella package. To
depend on it directly (e.g. from a non-Flutter Dart target):

```yaml
dependencies:
  dart_otel_exporter_otlp_http:
    git:
      url: https://github.com/cedricziel/flutter-otel
      path: packages/dart_otel_exporter_otlp_http
```

## Usage example

```dart
import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:dart_otel_exporter_otlp_http/dart_otel_exporter_otlp_http.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final exporter = OtlpHttpLogExporter(
    endpoint: Uri.parse('https://collector.example.com/v1/logs'),
    httpClient: http.Client(),
    headers: {'Authorization': 'Bearer <token>'},
  );

  final resource = OTelResource(serviceName: 'my-service');
  final result = await exporter.export(
    [LogRecord(body: 'hello', severity: LogSeverity.info)],
    resource,
  );

  print(result.success ? 'exported' : 'failed: ${result.error}');
  await exporter.shutdown();
}
```

## Testing

```bash
cd packages/dart_otel_exporter_otlp_http
dart pub get   # or rely on the workspace root's `flutter pub get`
dart analyze
dart test
```
