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
dart_otel_api ──> flutter_otel_native
```

Depends on `dart_otel_api` and `flutter` (for `MethodChannel`) only —
never on `dart_otel_sdk`, so it stays usable against any
`TracerProvider`/`LoggerProvider` implementation, not just the concrete SDK.

## What's in here

- **`NativeTelemetryBridge`** (Dart) — drains the native on-disk queue over
  a `MethodChannel` and forwards each record into a `TracerProvider`/
  `LoggerProvider` via the `ingestSpan`/`ingestLogRecord` methods added to
  `dart_otel_api` alongside this package. Also exposes
  `setSessionId`/`setCurrentTraceContext`/`clearCurrentTraceContext` so
  native records can be tagged with the current session/trace.
- **`NativeTelemetryRecorder`** (Swift, in the `NativeTelemetryCore`
  sub-package under `native/`) — the entry point future native
  instrumentation calls to record a finished span or log. Defaults a new
  record onto whatever trace context/session was last set, or starts a
  fresh root trace if nothing was set. Native instrumentation reaches the
  shared instance via `NativeTelemetry.shared` rather than constructing
  its own.
- **`RecordQueue`** (Swift) — the on-disk, capped, NDJSON-backed queue
  `NativeTelemetryRecorder` writes to, so recorded data survives until
  Dart is next able to drain it.

### Why `NativeTelemetryCore`'s sources are vendored into `ios/` and `macos/`

`native/NativeTelemetryCore` is the source of truth (and what `swift test`
runs against), but the `ios/flutter_otel_native/Sources/flutter_otel_native/
NativeTelemetryCore/` and `macos/.../NativeTelemetryCore/` folders hold a
duplicated copy of the same files, kept in sync by hand. Two more natural
approaches were tried first and both broke in practice:

- A nested `Package.swift` dependency (`.package(path:
"../../native/NativeTelemetryCore")`) fails under Flutter's Swift Package
  Manager plugin integration: Flutter copies a plugin's own package folder
  into the consuming app's `ephemeral/Packages/` directory, and that copy
  doesn't include sibling directories reached via `..`, so the relative
  path resolves to a location that doesn't exist. (This is why these two
  platform folders have no `Package.swift` at all — Flutter falls back to
  CocoaPods for this plugin.)
- A CocoaPods `source_files` glob reaching outside the pod's own directory
  (`../native/...`) is not reliably picked up by CocoaPods/Xcode project
  generation — the module ends up missing the symbols entirely.

Vendoring plain files inside each plugin's own `Sources/` tree sidesteps
both problems at the cost of manual sync.

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
