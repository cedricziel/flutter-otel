# flutter_otel_native

Native (Swift) telemetry foundation for `flutter_otel` on iOS and macOS: a
way for native code to record a finished span or log record — even before
or without a running Dart isolate — and have it flow into the same OTLP
export pipeline as everything recorded from Dart.

This is plumbing, not a feature on its own. It implements no instrumentation
by itself — no cold-start timing, no crash capture, no background-task
tracing, no native networking spans. Those are separate, later packages
built as thin call sites on top of `NativeTelemetryRecorder`. See
`docs/superpowers/specs/2026-09-12-native-telemetry-foundation-design.md`
in the repo root for the full design and what's explicitly deferred.

## Position in the dependency graph

```
flutter_otel_api ──> flutter_otel_native
```

Depends on `flutter_otel_api` and `flutter` (for `MethodChannel`) only —
never on `flutter_otel_sdk`, so it stays usable against any
`TracerProvider`/`LoggerProvider` implementation, not just the concrete SDK.

## What's in here

- **`NativeTelemetryBridge`** (Dart) — drains the native on-disk queue over
  a `MethodChannel` and forwards each record into a `TracerProvider`/
  `LoggerProvider` via the `ingestSpan`/`ingestLogRecord` methods added to
  `flutter_otel_api` alongside this package. Also exposes
  `setSessionId`/`setCurrentTraceContext`/`clearCurrentTraceContext` so
  native records can be tagged with the current session/trace.
- **`NativeTelemetryRecorder`** (Swift, in the `NativeTelemetryCore`
  sub-package under `native/`) — the entry point future native
  instrumentation calls to record a finished span or log. Defaults a new
  record onto whatever trace context/session was last set, or starts a
  fresh root trace if nothing was set.
- **`RecordQueue`** (Swift) — the on-disk, capped, NDJSON-backed queue
  `NativeTelemetryRecorder` writes to, so recorded data survives until
  Dart is next able to drain it.

## Usage

```dart
import 'package:flutter_otel/flutter_otel.dart';
import 'package:flutter_otel_native/flutter_otel_native.dart';

Future<void> main() async {
  final otel = await OTelSdk.initialize(/* ... */);

  final bridge = NativeTelemetryBridge();
  await bridge.setSessionId(otel.sessionManager!.sessionId);
  await bridge.drainAndForward(
    tracerProvider: otel.tracerProvider,
    loggerProvider: otel.loggerProvider,
  );

  runApp(const MyApp());
}
```

Nothing in this package calls `drainAndForward` automatically — call it
after `OTelSdk.initialize`, and again whenever else makes sense for your
app (e.g. on resume), until a later spec adds automatic wiring.

## Not yet implemented

- Cold-start / pre-engine span capture.
- Native crash capture (signal/exception handlers).
- Background-task tracing (`BGTaskScheduler`, push handling).
- Native (`URLSession`) networking instrumentation.
- Automatic wiring into `OTelSdk.initialize` or `Span.current`.
- Direct native export — native always hands data to Dart's existing OTLP
  exporters rather than talking to a collector itself.
