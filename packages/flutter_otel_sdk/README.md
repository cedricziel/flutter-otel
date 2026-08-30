# flutter_otel_sdk

The concrete OpenTelemetry SDK implementation for Flutter: log and span
processors, session tracking, and the `OTelSdk` facade. This is where the
interfaces declared in [`flutter_otel_api`](../flutter_otel_api/README.md)
get real implementations.

**Platform support:** iOS and macOS are the currently supported and tested
targets, matching the first consuming app. Session tracking's only
platform-touching piece is `WidgetsBindingObserver`, which is cross-platform
Flutter API with no native channel behind it — Android, web, Windows, and
Linux should work but are not yet verified.

## Position in the dependency graph

```
flutter_otel_api  ──┐
                     ├──> flutter_otel_sdk ──> flutter_otel (umbrella)
flutter_otel_exporter_otlp_http ──┘
```

Depends on `flutter_otel_api`, `flutter_otel_exporter_otlp_http`, `flutter`
(sdk), and `uuid`. Depended on by the `flutter_otel` umbrella package.

## What's in here

- `SimpleLogRecordProcessor` / `SimpleSpanProcessor` — export each
  record/finished span immediately; good for dev/tests.
- `BatchLogRecordProcessor` / `BatchSpanProcessor` — batch records/spans
  (`maxQueueSize`, `maxExportBatchSize`, `scheduledDelay`, shared across
  both signals), flushing on a periodic timer or once a batch fills up;
  swallow export failures via `debugPrint` instead of throwing into app
  code. Both guard against exporting during/after `shutdown()`.
- `SdkLoggerProvider` — the concrete `LoggerProvider`. Every `Logger` it
  vends automatically stamps `traceId`/`spanId` from `Span.current` onto
  each emitted record when a span is active (unless the caller already set
  them) — this is the trace-to-log correlation mechanism. When session
  tracking is enabled, it also merges a `session.id` attribute onto each
  record and calls `SessionManager.touch()`.
- `SdkSpan` / `SdkTracer` / `SdkTracerProvider` — the concrete traces
  pipeline. `SdkTracer.startActiveSpan` runs its callback inside
  `Span.runWithSpan` (a `dart:async` `Zone`), which is what makes
  `Span.current` — and therefore log correlation — automatic across `await`
  gaps and nested spans.
- `DefaultSessionManager` — generates a new session ID once more than the
  configured idle timeout (default 30 minutes) has elapsed between
  `touch()` calls, and (optionally) registers a `WidgetsBindingObserver` so
  resuming from the background after a long gap starts a new session.
- `OTelSdkConfig` / `OTelSdk` — the configuration object and top-level
  facade apps actually call. `OTelSdk` owns both the log and span
  processor/exporter pipelines; `forceFlush()`/`shutdown()` reach both.

## Install

Usually pulled in transitively via the `flutter_otel` umbrella package:

```yaml
dependencies:
  flutter_otel_sdk:
    git:
      url: https://github.com/cedricziel/flutter-otel
      path: packages/flutter_otel_sdk
```

## Usage example

```dart
import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:flutter_otel_sdk/flutter_otel_sdk.dart';

Future<void> main() async {
  final sdk = await OTelSdk.initialize(
    OTelSdkConfig(
      resource: OTelResource(serviceName: 'my-app'),
      // Bring your own exporters, e.g. flutter_otel_exporter_otlp_http's
      // OtlpHttpLogExporter/OtlpHttpSpanExporter, or fakes for tests.
      logExporter: const NoopLogRecordExporter(),
      spanExporter: const NoopSpanExporter(),
    ),
  );

  // A log emitted while this span is active is automatically stamped with
  // its traceId/spanId.
  await sdk.getTracer().startActiveSpan('startup', (span) async {
    sdk.getLogger().info('hello from flutter_otel_sdk');
  });
  await sdk.shutdown();
}
```

## Testing

```bash
cd packages/flutter_otel_sdk
flutter pub get   # or rely on the workspace root's `flutter pub get`
flutter analyze
flutter test
```
