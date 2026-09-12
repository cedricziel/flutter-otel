# Native telemetry foundation — design

Status: approved for implementation planning
Date: 2026-09-12

## Context

`flutter-otel` implements the logs and traces signals entirely in Dart,
targeting iOS and macOS as the tested platforms but with no native code and
no platform channels — everything runs inside the Dart isolate. That leaves
a real gap: telemetry for things that happen on the native side of an
iOS/macOS app, some of which occur when no Dart isolate is alive at all —
pre-`FlutterEngine` app launch, native crashes, background execution, and
native (non-Dio) networking.

Building all four of those in one pass was rejected as too large and too
risky to validate at once — each has different native lifecycle constraints
and none has been proven against real native code yet. This spec covers
only the shared plumbing all four need:

1. A way for native (Swift) code to record an already-finished span or log
   record, independent of whether Dart is currently running.
2. Durable, on-disk queuing so a record survives until Dart is next able to
   drain it.
3. A bridge that hands drained records into the existing Dart
   processor/exporter pipeline.
4. A minimal trace-context handoff so native-recorded telemetry composes
   into the same traces as Dart-recorded telemetry instead of being
   orphaned.

Cold-start timing, native crash capture, background-task tracing, and
native networking instrumentation are each separate, later specs built as
thin call sites on top of this foundation. None of them is implemented
here.

## Package

A new package, `flutter_otel_native`, added under `packages/` alongside the
existing ones, structured as a Flutter plugin:

```
packages/flutter_otel_native/
  pubspec.yaml            # platforms: ios, macos; depends on flutter_otel_api + flutter
  lib/
    flutter_otel_native.dart
    src/
      native_telemetry_bridge.dart
      native_record_codec.dart   # NDJSON line <-> SpanData/LogRecord
  ios/
    Classes/                     # symlinked/shared with macos/Classes via a
                                  # shared Swift source set (standard Flutter
                                  # federated-plugin pattern)
  macos/
    Classes/
```

It depends on `flutter_otel_api` (for `SpanData`, `LogRecord`, `SpanContext`
shapes) and `flutter` (for `MethodChannel`), the same dependency shape as
`flutter_otel_sdk`. It does not depend on `flutter_otel_sdk` directly —
`NativeTelemetryBridge.drainAndForward` takes a `TracerProvider` and
`LoggerProvider` (the interfaces), not the concrete SDK, so it stays
testable without pulling in the full SDK.

Consuming apps add `flutter_otel_native` alongside `flutter_otel` the same
way `flutter_otel_instrumentation_dio` is added today (git dependency +
`dependency_overrides`, per the root README's existing pattern).

## Data model & wire format

Native records are newline-delimited JSON (NDJSON), one JSON object per
line, appended to a single queue file. A `"kind"` field discriminates spans
from logs so both signals share one file and one drain call:

```json
{"kind": "span", "name": "app.launch.pre_engine", "traceId": "4bf92f3577b34da6a3ce929d0e0e4736", "spanId": "00f067aa0ba902b7", "parentSpanId": null, "spanKind": "internal", "startTimeUnixNano": "1700000000000000000", "endTimeUnixNano": "1700000000050000000", "attributes": {"os.name": "ios"}, "events": [], "statusCode": "unset", "statusDescription": null, "scopeName": "flutter_otel_native", "scopeVersion": "0.1.0"}
{"kind": "log", "timeUnixNano": "1700000000010000000", "severity": "info", "body": "native record", "attributes": {}, "traceId": null, "spanId": null}
```

- Field names and shapes mirror `SpanData`/`LogRecord` (`flutter_otel_api`)
  directly so `native_record_codec.dart` is a near-literal
  `fromJson`/`toJson`, not a translation layer with its own semantics.
- IDs use exactly the format `SpanContext` already validates: a trace ID is
  16 random bytes as 32 lowercase hex characters, a span ID is 8 random
  bytes as 16 lowercase hex characters. Native generates these with
  `SecRandomCopyBytes` (falling back to `arc4random_buf` if unavailable) —
  no new ID scheme, no coordination with Dart's ID generation needed since
  both sides independently produce spec-conformant random IDs.
- NDJSON (append-only, one line per record) rather than rewriting a whole
  file or a structured format (plist/SQLite): appending a line from Swift is
  a single `FileHandle.seekToEndOfFile()` + `write(_:)`, requires no schema
  migration story, and drains line-by-line trivially from Dart.
- The queue file lives in the app's own container (`Application Support` on
  both iOS and macOS) — not App Group / shared storage. App extensions and
  true headless background execution are out of scope for this spec (they
  belong to the background-task-tracing follow-on, which may need to
  revisit storage location).

## Native-side components (Swift)

- **`NativeTelemetryRecorder`** — the only entry point future native
  instrumentation calls:
  ```swift
  func recordSpan(name: String, traceId: String?, spanId: String?,
                   parentSpanId: String?, kind: SpanKind, start: Date,
                   end: Date, attributes: [String: Any], events: [SpanEvent],
                   statusCode: StatusCode, statusDescription: String?)
  func recordLog(body: String, severity: LogSeverity, timestamp: Date,
                  attributes: [String: Any])
  ```
  When `traceId`/`spanId` aren't supplied, it generates a fresh root pair
  itself. If `NativeTraceContext` (below) currently holds a value and the
  caller didn't pass explicit IDs, the new record's `traceId` is taken from
  it and a fresh `spanId` is generated with `parentSpanId` set to the held
  span ID — i.e. it attaches as a child by default rather than always
  rooting.
- **`NativeTraceContext`** — a small in-memory (not persisted) holder for
  "the trace context Dart last told native about" via
  `setCurrentTraceContext`/`clearCurrentTraceContext` (see below). Read by
  `NativeTelemetryRecorder`, written only by the bridge's method-channel
  handler.
- **`RecordQueue`** — appends NDJSON lines to the queue file on a serial
  `DispatchQueue` (safe from any calling thread), enforces the record cap
  (below), and implements the atomic drain-and-clear used by
  `drainQueue()`.
- Explicitly **not** signal-handler-safe: no async-signal-safe allocation or
  file I/O guarantees are made here. A future crash-capture spec that needs
  to record from inside a signal handler will need its own narrower,
  signal-safe write path — this recorder is for normal (non-signal-handler)
  native code paths only.

## Platform-channel bridge

One `MethodChannel('flutter_otel_native')`, three methods:

- **`drainQueue()`** → `List<String>`. Reads all queued NDJSON lines,
  returns them to Dart, and clears the file only after Dart's call returns
  successfully (i.e. the native side clears on completion of the same
  invocation that returned the data, so a crash between "data returned" and
  "file cleared" can at worst cause one re-delivered batch on next drain,
  never silent loss — Dart-side ingestion below is idempotent-safe against
  this because re-ingesting the same `SpanData`/`LogRecord` twice is only a
  duplicate-export risk, not a correctness bug).
- **`setCurrentTraceContext(traceId: String, spanId: String)`** /
  **`clearCurrentTraceContext()`** → sets/clears `NativeTraceContext`. This
  spec ships the channel method and its native-side effect, tested
  directly; it does **not** wire up automatic invocation on every Dart span
  change (e.g. via a `Span.current` listener) — that belongs to whichever
  follow-on spec first needs it (crash capture is the likely first
  consumer).
- **`recordTestEvent(kind: String, ...)`** — debug-only convenience so
  integration/unit tests can push a record through `RecordQueue` without
  writing throwaway Swift test scaffolding per test. Guarded so it's a
  no-op in release builds if it turns out to matter for binary size (TBD at
  implementation time; not a design-affecting decision).

Dart side: `NativeTelemetryBridge`, the package's one public class.

```dart
class NativeTelemetryBridge {
  NativeTelemetryBridge({MethodChannel? channel}); // channel injectable for tests

  /// Drains the native queue and forwards every record into [tracerProvider]
  /// / [loggerProvider] via ingestSpan/ingestLogRecord. Malformed lines are
  /// skipped and counted, never thrown.
  Future<NativeDrainResult> drainAndForward({
    required TracerProvider tracerProvider,
    required LoggerProvider loggerProvider,
  });

  /// Tags subsequent native records with [sessionId] as a `session.id`
  /// attribute. Call once at startup and again whenever the session rolls.
  Future<void> setSessionId(String sessionId);

  Future<void> setCurrentTraceContext(SpanContext context);
  Future<void> clearCurrentTraceContext();
}

class NativeDrainResult {
  final int recordsIngested;
  final int recordsSkipped; // malformed JSON
  final int recordsDropped; // reported by native as cap-evicted since last drain
}
```

Consuming apps call `drainAndForward` after `OTelSdk.initialize` (this spec
does not wire it automatically into `OTelSdk.initialize` — that's a
one-line follow-up left to whichever consumer/spec needs the convenience,
since forcing every `flutter_otel` user to depend on
`flutter_otel_native` is out of scope here).

## Core SDK change: ingestion

Today there is no way to feed an already-finished `SpanData`/`LogRecord`
into the pipeline — `SpanProcessor.onEnd`/`LogRecordProcessor.onEmit` exist,
but aren't reachable from `TracerProvider`/`LoggerProvider`. This spec adds
one additive method to each interface in `flutter_otel_api`:

```dart
abstract class TracerProvider {
  ...
  /// Feeds an externally-produced (already-finished) span directly into
  /// the processor pipeline — e.g. one recorded natively before Dart ran.
  void ingestSpan(SpanData span);
}

abstract class LoggerProvider {
  ...
  void ingestLogRecord(LogRecord record);
}
```

`SdkTracerProvider`/`SdkLoggerProvider` (the only current implementations
of each interface) implement these as a direct passthrough to their
processor's `onEnd`/`onEmit`. `NoopTracerProvider` implements `ingestSpan`
as a no-op; there is no `NoopLoggerProvider` today, so no equivalent change
is needed on the logs side. This is generically useful (any future
out-of-process or replay source), not native-specific plumbing bolted onto
the core.

## Trace continuity & session correlation

- **Native → Dart (root handoff):** a native record with no parent (nothing
  in `NativeTraceContext` at record time) carries its own natively-generated
  `traceId`/`spanId`. Dart's ingestion uses them as-is — `SpanData`/
  `LogRecord` already carry explicit IDs, so no new mechanism is needed.
  Whether/how a _later_ Dart span joins that same trace (e.g. cold-start's
  first Dart span continuing the native pre-engine trace) is the cold-start
  spec's problem: it will use `Tracer.startSpan(..., parentContext:)`,
  which already exists.
- **Dart → Native (child attach):** `setCurrentTraceContext` exists as a
  primitive (tested directly against `NativeTraceContext`) but nothing in
  this spec calls it automatically. Wiring "call `setCurrentTraceContext`
  every time `Span.current` changes" is deferred to the first consumer that
  needs it.
- **Session correlation:** `NativeTelemetryBridge.setSessionId` tags
  subsequent native records with a `session.id` attribute, mirroring how
  logs already correlate to `SessionManager.sessionId` in
  `flutter_otel_sdk`. The consumer app is responsible for calling it at
  startup and on session rollover — this spec doesn't hook
  `SessionManager` automatically, keeping `flutter_otel_native`
  independent of `flutter_otel_sdk`.

## Reliability

- `RecordQueue` caps the file at 500 records by default (matching the
  order of magnitude of `OTelSdkConfig.maxQueueSize`'s existing default),
  dropping the oldest record on overflow. The drop count since the last
  drain is reported back in the next `drainQueue()` response so loss is
  visible (`NativeDrainResult.recordsDropped`) rather than silent.
- A line that fails JSON decoding during drain is skipped and counted
  (`recordsSkipped`) rather than aborting the whole drain.

## Testing

- **Swift (XCTest):** `RecordQueue` — append/drain/clear, cap eviction,
  drain-then-crash-simulation (verify clear only happens after the
  simulated "Dart acknowledged" callback), corrupt-line survival.
  `NativeTelemetryRecorder` — default ID generation, child-attach when
  `NativeTraceContext` is set.
- **Dart:** `NativeTelemetryBridge` tested against a fake `MethodChannel`
  (`TestDefaultBinaryMessengerBinding.setMockMethodCallHandler`) covering:
  NDJSON → `SpanData`/`LogRecord` decoding, malformed-line skip counting,
  correct `ingestSpan`/`ingestLogRecord` calls on fake `TracerProvider`/
  `LoggerProvider` test doubles, `setSessionId`/`setCurrentTraceContext`
  argument marshaling.
- **`flutter_otel_api` core change:** unit tests for
  `SdkTracerProvider.ingestSpan`/`SdkLoggerProvider.ingestLogRecord`
  passthrough to the configured processor.
- No end-to-end (real simulator/device) integration test in this spec —
  there's no real native instrumentation yet to exercise meaningfully.
  Deferred to the cold-start spec, which will have real native call sites
  to assert against.

## Out of scope (explicitly deferred to later specs)

- Cold-start / pre-engine span capture.
- Native crash capture (signal/exception handlers) — including the
  signal-handler-safe write path `NativeTelemetryRecorder` explicitly does
  not provide.
- Background-task tracing (`BGTaskScheduler`, push handling) — including
  whatever storage-location change headless/App-Group execution turns out
  to need.
- Native (URLSession) networking instrumentation.
- Automatic wiring of `OTelSdk.initialize` to call `drainAndForward`, or of
  `Span.current` changes to call `setCurrentTraceContext` — both primitives
  exist after this spec but neither is auto-invoked.
- Direct native export (an OTLP/HTTP exporter written in Swift) — rejected
  in favor of always handing off to Dart's existing exporters.
