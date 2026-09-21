# dart_otel_api

Platform-agnostic OpenTelemetry core for [flutter_otel](../../README.md):
`OTelResource`, the logs signal contracts (fully implemented), the traces
signal contracts (fully implemented, including `Span.current` for
trace-to-log correlation and W3C Trace Context propagation helpers), and a
minimal metrics stub so the shape is visibly ready for that signal later.

Pure Dart — **no Flutter, `http`, or `uuid` dependency** — so it can be
depended on from any Dart target (Flutter apps, but also server, CLI, or web
code), not just this workspace's Flutter-based packages.

## Position in the dependency graph

This is the foundation package. Nothing in the workspace depends on
anything *but* this package plus their own extra needs:

```text
dart_otel_api  <── dart_otel_sdk
                  <── dart_otel_exporter_otlp_http
                  <── dart_otel_instrumentation_dio
                  <── flutter_otel (umbrella)
```

It has no dependencies on other workspace members.

## What's in here

- `OTelResource` — describes the app/service producing telemetry.
- `LogSeverity`, `LogRecord` — the logs data model.
- `Logger`, `LoggerProvider`, `LogRecordProcessor`, `LogRecordExporter` —
  the interfaces every concrete logs implementation (in `dart_otel_sdk`
  and `dart_otel_exporter_otlp_http`) is built against.
- `NoopLogRecordExporter` — a zero-I/O exporter, used when the SDK is
  disabled.
- `ExportResult` — the shared success/failure result type every exporter
  (any signal) returns.
- `encodeAnyValue` / `encodeAttributes` — OTLP JSON `AnyValue` encoding
  helpers, shared by every OTLP/HTTP exporter.
- `SessionManager` — the session-tracking interface (the default
  implementation, which needs `WidgetsBindingObserver`, lives in
  `dart_otel_sdk`).
- `SpanContext`, `SpanKind`, `StatusCode`, `SpanEvent`, `SpanData` — the
  traces data model (`SpanData` is the immutable finished-span snapshot
  handed to exporters, analogous to `LogRecord`).
- `Span`, `Tracer`, `TracerProvider`, `SpanProcessor`, `SpanExporter` — the
  interfaces every concrete traces implementation (in `dart_otel_sdk` and
  `dart_otel_exporter_otlp_http`) is built against.
- `Span.current` / `Span.runWithSpan` — the ambient "current span" (backed
  by a `dart:async` `Zone` value) that `Tracer.startActiveSpan`
  implementations set, and that `dart_otel_sdk`'s logger reads to
  automatically correlate logs with the active span.
- `NoopTracer` / `NoopTracerProvider` / `NoopSpanExporter` — no-op
  implementations used when tracing has no backing SDK, or when the SDK is
  disabled.
- `formatTraceparent` / `parseTraceparent` — encode/decode a W3C Trace
  Context `traceparent` header, for propagating the active trace across an
  outgoing HTTP request (used by `dart_otel_instrumentation_dio`).
- `Meter` / `MeterProvider` with `Noop*` implementations — a placeholder
  proving the core doesn't need to change shape when metrics are
  implemented for real.

## Install

Usually pulled in transitively via the `flutter_otel` umbrella package.
To depend on it directly (e.g. to implement a custom exporter):

```yaml
dependencies:
  dart_otel_api:
    git:
      url: https://github.com/cedricziel/flutter-otel
      path: packages/dart_otel_api
```

## Usage example

```dart
import 'package:dart_otel_api/dart_otel_api.dart';

class PrintingLogRecordExporter implements LogRecordExporter {
  @override
  Future<ExportResult> export(List<LogRecord> records, OTelResource resource) async {
    for (final record in records) {
      print('[${record.severity.severityText}] ${record.body} ${record.attributes}');
    }
    return const ExportResult.success();
  }

  @override
  Future<void> shutdown() async {}
}
```

## Testing

```bash
cd packages/dart_otel_api
dart pub get   # or rely on the workspace root's `flutter pub get`
dart analyze
dart test
```
