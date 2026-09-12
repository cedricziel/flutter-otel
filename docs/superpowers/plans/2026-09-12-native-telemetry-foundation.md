# Native Telemetry Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give native (Swift) iOS/macOS code a way to record finished spans/log records — even before or without a running Dart isolate — and hand them into `flutter-otel`'s existing OTLP export pipeline, as the shared foundation for later cold-start, crash-capture, background-task, and native-networking work.

**Architecture:** A new Flutter plugin package, `flutter_otel_native`, pairs a pure-Swift, Flutter-independent core (`NativeTelemetryCore`: ID generation, an NDJSON-backed on-disk queue, a recorder that defaults new records onto whatever trace/session context Dart last told it about) with a thin `FlutterPlugin` that exposes it over one `MethodChannel`. On the Dart side, `NativeTelemetryBridge` drains that channel and decodes each NDJSON line into the existing `SpanData`/`LogRecord` types, then feeds them into two small additive methods — `TracerProvider.ingestSpan`/`LoggerProvider.ingestLogRecord` — added to `flutter_otel_api`'s core interfaces so an already-finished record can enter the processor/exporter pipeline without going through `Tracer.startSpan`.

**Tech Stack:** Dart 3 (pattern matching, sealed classes), Flutter plugin platform channels, Swift 5.9 / Swift Package Manager, XCTest, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-12-native-telemetry-foundation-design.md`

## Global Constraints

- Dart SDK constraint `^3.6.0`, Flutter constraint `>=3.27.0` (matches every existing Flutter-dependent package in this workspace).
- New package platform floors: iOS 15.0, macOS 12.0 (matches Flutter's current plugin template defaults). Swift tools version 5.9.
- `flutter_otel_native` depends on `flutter_otel_api` and `flutter` only — never on `flutter_otel_sdk` (per spec: `NativeTelemetryBridge` takes `TracerProvider`/`LoggerProvider` interfaces, not the concrete SDK).
- MethodChannel name: `'flutter_otel_native'`.
- Wire format (finalized here; every task must match these field names exactly):
  - Span line: `{"kind":"span","name":string,"traceId":string,"spanId":string,"parentSpanId":string?,"spanKind":"internal"|"server"|"client"|"producer"|"consumer","startTimeUnixNano":string,"endTimeUnixNano":string,"attributes":object,"events":[{"name":string,"timeUnixNano":string,"attributes":object}],"statusCode":"unset"|"ok"|"error","statusDescription":string?,"scopeName":string,"scopeVersion":string?}`
  - Log line: `{"kind":"log","timeUnixNano":string,"severity":"trace"|"debug"|"info"|"warn"|"error"|"fatal","body":string,"attributes":object,"traceId":string?,"spanId":string?}`
  - Optional fields are simply omitted (not written as JSON `null`) when absent; Dart decoding treats a missing key as `null`.
- `drainQueue()` channel method returns a `Map` — `{"records": [String], "droppedSinceLastDrain": int}` — not a bare list, so the drop count travels with every drain.
- No `NoopLoggerProvider` exists in this codebase — only `SdkLoggerProvider` implements `LoggerProvider`, so `ingestLogRecord` has exactly one production implementation to update.
- Native recording is **not** signal-handler-safe; that constraint belongs to a future crash-capture spec, not this one.
- No automatic wiring: nothing in this plan calls `drainAndForward` from `OTelSdk.initialize`, and nothing calls `setCurrentTraceContext` automatically from `Span.current` changes. Both are primitives only.
- **Plan-level simplification vs. the spec's phrasing:** the spec's platform-channel section describes an ack-style drain ("native clears... only after Dart's call returns successfully"). This plan implements the simpler, equivalent behavior of clearing the on-disk queue synchronously as part of producing the drain result (native reads-then-clears in one call), which trades a small crash-during-flush loss window for much less complexity. This is called out to the user before implementation begins (see chat) since it's a real, if minor, behavior difference from the spec's wording — not a silent deviation.
- `RecordQueue`'s default cap is 2048 records, matching `OTelSdkConfig.maxQueueSize`'s existing default exactly (`packages/flutter_otel_sdk/lib/src/otel_sdk_config.dart:17`).
- Semantic commit per task (`feat:`, `test:` only where a task is test-only, `docs:`, `chore:`); each task's commit bundles its test(s) and implementation together, matching this repo's existing history style.

---

## Task 1: Core ingestion — `TracerProvider.ingestSpan`

**Files:**

- Modify: `packages/flutter_otel_api/lib/src/trace/tracer_provider.dart`
- Modify: `packages/flutter_otel_sdk/lib/src/sdk_tracer_provider.dart`
- Test: `packages/flutter_otel_api/test/tracer_test.dart`
- Test: `packages/flutter_otel_sdk/test/sdk_tracer_provider_test.dart`

**Interfaces:**

- Produces: `TracerProvider.ingestSpan(SpanData span)` (abstract, in `flutter_otel_api`), used directly by `NativeTelemetryBridge.drainAndForward` in Task 4.
- Consumes: `SpanData` (`flutter_otel_api/lib/src/trace/span_data.dart`, already exists), `SpanProcessor.onEnd(SpanData)` (already exists, called internally by `SdkTracerProvider.ingestSpan`).

- [ ] **Step 1: Write the failing tests**

Add to `packages/flutter_otel_api/test/tracer_test.dart`, inside the existing `group('NoopTracerProvider', () { ... })` block (after the `forceFlush and shutdown` test):

```dart
    test('ingestSpan does not throw', () {
      const provider = NoopTracerProvider();
      final span = provider.getTracer().startSpan('op');
      span.end();

      expect(() => provider.ingestSpan(span.spanContext as dynamic), returnsNormally);
    });
```

Replace that placeholder body — `NoopTracer.startSpan` returns a `Span`, not a `SpanData`, so build a real `SpanData` directly instead:

```dart
    test('ingestSpan does not throw', () {
      const provider = NoopTracerProvider();
      final span = SpanData(
        name: 'op',
        spanContext: const SpanContext(
          traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
          spanId: '00f067aa0ba902b7',
        ),
        startTime: DateTime.now(),
        endTime: DateTime.now(),
      );

      expect(() => provider.ingestSpan(span), returnsNormally);
    });
```

Add to `packages/flutter_otel_sdk/test/sdk_tracer_provider_test.dart`, as a new top-level `group` after the existing `group('SdkTracerProvider.forceFlush/shutdown', ...)`:

```dart
  group('SdkTracerProvider.ingestSpan', () {
    test('forwards the span to the configured processor unchanged', () {
      final provider = SdkTracerProvider(processor: processor);
      final span = SpanData(
        name: 'native.op',
        spanContext: const SpanContext(
          traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
          spanId: '00f067aa0ba902b7',
        ),
        startTime: DateTime.now(),
        endTime: DateTime.now(),
      );

      provider.ingestSpan(span);

      expect(exporter.allSpans, isEmpty); // SimpleSpanProcessor is sync but
      // exports async; force a flush to observe it.
    });

    test('the ingested span is exported after forceFlush', () async {
      final provider = SdkTracerProvider(processor: processor);
      final span = SpanData(
        name: 'native.op',
        spanContext: const SpanContext(
          traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
          spanId: '00f067aa0ba902b7',
        ),
        startTime: DateTime.now(),
        endTime: DateTime.now(),
      );

      provider.ingestSpan(span);
      await provider.forceFlush();

      expect(exporter.allSpans, [same(span)]);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/flutter_otel_api && dart test test/tracer_test.dart`
Expected: FAIL — `The method 'ingestSpan' isn't defined for the type 'NoopTracerProvider'`.

Run: `cd packages/flutter_otel_sdk && flutter test test/sdk_tracer_provider_test.dart`
Expected: FAIL — `The method 'ingestSpan' isn't defined for the type 'SdkTracerProvider'`.

- [ ] **Step 3: Add `ingestSpan` to the `TracerProvider` interface and `NoopTracerProvider`**

In `packages/flutter_otel_api/lib/src/trace/tracer_provider.dart`, add the import and the two method additions:

```dart
import 'span_data.dart';
import 'tracer.dart';

/// Vends [Tracer]s, mirroring `LoggerProvider`'s shape for the traces
/// signal.
abstract class TracerProvider {
  /// Returns a [Tracer] for the given instrumentation scope.
  Tracer getTracer({String name = 'flutter_otel', String? version});

  /// Feeds an externally-produced (already-finished) span directly into
  /// the processor pipeline — e.g. one recorded natively before Dart ran.
  void ingestSpan(SpanData span);

  /// Forces any buffered spans to be exported now.
  Future<void> forceFlush();

  /// Flushes and releases the underlying pipeline.
  Future<void> shutdown();
}

/// No-op [TracerProvider] used when tracing has no backing SDK. Always
/// returns a [NoopTracer]; flush/shutdown/ingestSpan are instant no-ops.
class NoopTracerProvider implements TracerProvider {
  const NoopTracerProvider();

  @override
  Tracer getTracer({String name = 'flutter_otel', String? version}) =>
      NoopTracer(name);

  @override
  void ingestSpan(SpanData span) {}

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
```

- [ ] **Step 4: Implement `ingestSpan` in `SdkTracerProvider`**

In `packages/flutter_otel_sdk/lib/src/sdk_tracer_provider.dart`, add after `getTracer`:

```dart
  @override
  void ingestSpan(SpanData span) => processor.onEnd(span);
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/flutter_otel_api && dart test test/tracer_test.dart`
Expected: PASS

Run: `cd packages/flutter_otel_sdk && flutter test test/sdk_tracer_provider_test.dart`
Expected: PASS

- [ ] **Step 6: Analyze and commit**

Run: `cd packages/flutter_otel_api && dart analyze && cd ../flutter_otel_sdk && flutter analyze`
Expected: no issues.

```bash
git add packages/flutter_otel_api/lib/src/trace/tracer_provider.dart \
        packages/flutter_otel_api/test/tracer_test.dart \
        packages/flutter_otel_sdk/lib/src/sdk_tracer_provider.dart \
        packages/flutter_otel_sdk/test/sdk_tracer_provider_test.dart
git commit -m "feat(otel-api): add TracerProvider.ingestSpan for pre-finished spans"
```

---

## Task 2: Core ingestion — `LoggerProvider.ingestLogRecord`

**Files:**

- Modify: `packages/flutter_otel_api/lib/src/logs/logger_provider.dart`
- Modify: `packages/flutter_otel_sdk/lib/src/sdk_logger_provider.dart`
- Test: `packages/flutter_otel_sdk/test/sdk_logger_provider_test.dart`

**Interfaces:**

- Produces: `LoggerProvider.ingestLogRecord(LogRecord record)` (abstract, in `flutter_otel_api`), used directly by `NativeTelemetryBridge.drainAndForward` in Task 4.
- Consumes: `LogRecord` (already exists), `LogRecordProcessor.onEmit(LogRecord)` (already exists).

- [ ] **Step 1: Write the failing test**

Add to `packages/flutter_otel_sdk/test/sdk_logger_provider_test.dart`, as a new top-level `group`:

```dart
  group('SdkLoggerProvider.ingestLogRecord', () {
    test('forwards the record to the configured processor unchanged',
        () async {
      final processor = SimpleLogRecordProcessor(exporter, resource);
      final provider = SdkLoggerProvider(resource: resource, processor: processor);
      final record = LogRecord(body: 'native log');

      provider.ingestLogRecord(record);
      await processor.forceFlush();

      expect(exporter.allRecords, [same(record)]);
    });
  });
```

(`allRecords` is a real getter on `FakeLogRecordExporter` — `packages/flutter_otel_sdk/test/support/fake_log_record_exporter.dart:46` — that flattens `exportedBatches`, mirroring `FakeSpanExporter.allSpans`.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/flutter_otel_sdk && flutter test test/sdk_logger_provider_test.dart`
Expected: FAIL — `The method 'ingestLogRecord' isn't defined for the type 'SdkLoggerProvider'`.

- [ ] **Step 3: Add `ingestLogRecord` to the `LoggerProvider` interface**

In `packages/flutter_otel_api/lib/src/logs/logger_provider.dart`:

```dart
import 'log_record.dart';

/// Vends named [Logger] instances and owns the flush/shutdown lifecycle of
/// whatever pipeline sits behind them.
abstract class LoggerProvider {
  /// Returns a [Logger] for the given instrumentation scope. Implementations
  /// typically cache and return the same instance for a given
  /// name/version pair.
  Logger getLogger({String name = 'flutter_otel', String? version});

  /// Feeds an externally-produced [LogRecord] directly into the processor
  /// pipeline — e.g. one recorded natively before Dart ran.
  void ingestLogRecord(LogRecord record);

  /// Forces any buffered records to be exported now. Resolves once the
  /// attempt (successful or not) has completed.
  Future<void> forceFlush();

  /// Flushes and releases any resources (timers, HTTP clients) held by the
  /// underlying pipeline. After this resolves, loggers obtained from this
  /// provider should no longer be used.
  Future<void> shutdown();
}
```

- [ ] **Step 4: Implement `ingestLogRecord` in `SdkLoggerProvider`**

In `packages/flutter_otel_sdk/lib/src/sdk_logger_provider.dart`, add inside the `SdkLoggerProvider` class, after `getLogger`:

```dart
  @override
  void ingestLogRecord(LogRecord record) => processor.onEmit(record);
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/flutter_otel_sdk && flutter test test/sdk_logger_provider_test.dart`
Expected: PASS

- [ ] **Step 6: Analyze and commit**

Run: `cd packages/flutter_otel_api && dart analyze && cd ../flutter_otel_sdk && flutter analyze`
Expected: no issues.

```bash
git add packages/flutter_otel_api/lib/src/logs/logger_provider.dart \
        packages/flutter_otel_sdk/lib/src/sdk_logger_provider.dart \
        packages/flutter_otel_sdk/test/sdk_logger_provider_test.dart
git commit -m "feat(otel-api): add LoggerProvider.ingestLogRecord for pre-finished records"
```

---

## Task 3: Scaffold `flutter_otel_native` + `NativeRecordCodec`

**Files:**

- Create: `packages/flutter_otel_native/pubspec.yaml`
- Create: `packages/flutter_otel_native/analysis_options.yaml`
- Create: `packages/flutter_otel_native/LICENSE` (copy of root `LICENSE`)
- Create: `packages/flutter_otel_native/lib/flutter_otel_native.dart`
- Create: `packages/flutter_otel_native/lib/src/native_record_codec.dart`
- Create: `packages/flutter_otel_native/test/native_record_codec_test.dart`

**Interfaces:**

- Consumes: `SpanData`, `SpanContext`, `SpanKind`, `StatusCode`, `SpanEvent`, `LogRecord`, `LogSeverity`, `defaultInstrumentationScopeName` (all from `flutter_otel_api`, already exist).
- Produces: `sealed class NativeRecord`, `class NativeSpanRecord extends NativeRecord` (field `spanData`), `class NativeLogRecord extends NativeRecord` (field `logRecord`), `NativeRecord? decodeNativeRecordLine(String line)` — used by `NativeTelemetryBridge.drainAndForward` in Task 4.

- [ ] **Step 1: Create the package manifest**

`packages/flutter_otel_native/pubspec.yaml`:

```yaml
name: flutter_otel_native
description: >
  Native (Swift) telemetry foundation for flutter_otel on iOS/macOS: an
  on-disk queue that lets native code record finished spans/log records
  before or without a running Dart isolate, plus a MethodChannel bridge
  that drains it into the existing TracerProvider/LoggerProvider pipeline.
version: 0.1.0
homepage: https://github.com/cedricziel/flutter-otel

environment:
  sdk: ^3.6.0
  flutter: ">=3.27.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_otel_api: ^0.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

resolution: workspace

flutter:
  plugin:
    platforms:
      ios:
        pluginClass: FlutterOtelNativePlugin
      macos:
        pluginClass: FlutterOtelNativePlugin
```

`packages/flutter_otel_native/analysis_options.yaml` (matches `flutter_otel_sdk`'s, the other Flutter-dependent package):

```yaml
analyzer:
  exclude:
    - build/**
include: package:flutter_lints/flutter.yaml
```

Copy the license file so the podspecs added in Task 9 have something to reference within the package directory:

```bash
cp LICENSE packages/flutter_otel_native/LICENSE
```

Register the new package as a workspace member — in the root `pubspec.yaml`, add it to the `workspace:` list:

```yaml
workspace:
  - packages/flutter_otel_api
  - packages/flutter_otel_sdk
  - packages/flutter_otel_exporter_otlp_http
  - packages/flutter_otel
  - packages/flutter_otel_instrumentation_dio
  - packages/flutter_otel_native
```

Run `flutter pub get` at the repo root once these exist (needed before any test in this package can run):

Run: `flutter pub get`
Expected: resolves without error (the package has no `lib/` content yet, which is fine).

- [ ] **Step 2: Write the failing test for `NativeRecordCodec`**

`packages/flutter_otel_native/test/native_record_codec_test.dart`:

```dart
import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:flutter_otel_native/src/native_record_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeNativeRecordLine', () {
    test('decodes a span line into a NativeSpanRecord', () {
      const line = '{"kind":"span","name":"app.launch.pre_engine",'
          '"traceId":"4bf92f3577b34da6a3ce929d0e0e4736",'
          '"spanId":"00f067aa0ba902b7","parentSpanId":null,'
          '"spanKind":"internal","startTimeUnixNano":"1700000000000000000",'
          '"endTimeUnixNano":"1700000000050000000",'
          '"attributes":{"os.name":"ios"},"events":[],'
          '"statusCode":"unset","scopeName":"flutter_otel_native",'
          '"scopeVersion":"0.1.0"}';

      final record = decodeNativeRecordLine(line);

      expect(record, isA<NativeSpanRecord>());
      final span = (record as NativeSpanRecord).spanData;
      expect(span.name, 'app.launch.pre_engine');
      expect(span.spanContext.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(span.spanContext.spanId, '00f067aa0ba902b7');
      expect(span.parentSpanId, isNull);
      expect(span.kind, SpanKind.internal);
      expect(span.attributes, {'os.name': 'ios'});
      expect(span.events, isEmpty);
      expect(span.statusCode, StatusCode.unset);
      expect(span.scopeName, 'flutter_otel_native');
      expect(span.scopeVersion, '0.1.0');
      expect(
        span.startTime.difference(
          DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ),
        Duration.zero,
      );
    });

    test('decodes a span line with a parent and an event', () {
      const line = '{"kind":"span","name":"child","traceId":'
          '"4bf92f3577b34da6a3ce929d0e0e4736","spanId":'
          '"00f067aa0ba902b7","parentSpanId":"a1b2c3d4e5f60708",'
          '"spanKind":"client","startTimeUnixNano":"1700000000000000000",'
          '"endTimeUnixNano":"1700000000050000000","attributes":{},'
          '"events":[{"name":"retry","timeUnixNano":"1700000000010000000",'
          '"attributes":{"attempt":1}}],"statusCode":"error",'
          '"statusDescription":"timed out","scopeName":"flutter_otel_native"}';

      final record = decodeNativeRecordLine(line) as NativeSpanRecord;
      final span = record.spanData;

      expect(span.parentSpanId, 'a1b2c3d4e5f60708');
      expect(span.kind, SpanKind.client);
      expect(span.statusCode, StatusCode.error);
      expect(span.statusDescription, 'timed out');
      expect(span.events, hasLength(1));
      expect(span.events.single.name, 'retry');
      expect(span.events.single.attributes, {'attempt': 1});
    });

    test('decodes a log line into a NativeLogRecord', () {
      const line = '{"kind":"log","timeUnixNano":"1700000000010000000",'
          '"severity":"warn","body":"native record",'
          '"attributes":{"count":3},'
          '"traceId":"4bf92f3577b34da6a3ce929d0e0e4736",'
          '"spanId":"00f067aa0ba902b7"}';

      final record = decodeNativeRecordLine(line);

      expect(record, isA<NativeLogRecord>());
      final log = (record as NativeLogRecord).logRecord;
      expect(log.body, 'native record');
      expect(log.severity, LogSeverity.warn);
      expect(log.attributes, {'count': 3});
      expect(log.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(log.spanId, '00f067aa0ba902b7');
    });

    test('decodes a log line with no trace context', () {
      const line = '{"kind":"log","timeUnixNano":"1700000000010000000",'
          '"severity":"info","body":"hello","attributes":{}}';

      final log = (decodeNativeRecordLine(line) as NativeLogRecord).logRecord;

      expect(log.traceId, isNull);
      expect(log.spanId, isNull);
    });

    test('returns null for invalid JSON', () {
      expect(decodeNativeRecordLine('not json'), isNull);
    });

    test('returns null for an unrecognized kind', () {
      expect(decodeNativeRecordLine('{"kind":"metric"}'), isNull);
    });

    test('returns null when a required field is missing', () {
      expect(decodeNativeRecordLine('{"kind":"span","name":"x"}'), isNull);
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd packages/flutter_otel_native && flutter test test/native_record_codec_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:flutter_otel_native/src/native_record_codec.dart'`.

- [ ] **Step 4: Implement `NativeRecordCodec`**

`packages/flutter_otel_native/lib/src/native_record_codec.dart`:

```dart
import 'dart:convert';

import 'package:flutter_otel_api/flutter_otel_api.dart';

/// One decoded line from the native queue: either a span or a log record.
sealed class NativeRecord {}

/// A decoded span line, ready to be fed into
/// `TracerProvider.ingestSpan`.
class NativeSpanRecord extends NativeRecord {
  NativeSpanRecord(this.spanData);

  final SpanData spanData;
}

/// A decoded log line, ready to be fed into
/// `LoggerProvider.ingestLogRecord`.
class NativeLogRecord extends NativeRecord {
  NativeLogRecord(this.logRecord);

  final LogRecord logRecord;
}

/// Decodes one NDJSON line produced by the native queue into a
/// [NativeRecord]. Returns `null` when the line is malformed — invalid
/// JSON, not a JSON object, an unrecognized `"kind"`, or missing a field
/// required for that kind — so callers can count and skip it rather than
/// crash the whole drain.
NativeRecord? decodeNativeRecordLine(String line) {
  try {
    final json = jsonDecode(line);
    if (json is! Map<String, Object?>) return null;
    return switch (json['kind']) {
      'span' => NativeSpanRecord(_decodeSpanData(json)),
      'log' => NativeLogRecord(_decodeLogRecord(json)),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

SpanData _decodeSpanData(Map<String, Object?> json) {
  final eventsJson = (json['events'] as List?) ?? const [];
  return SpanData(
    name: json['name']! as String,
    spanContext: SpanContext(
      traceId: json['traceId']! as String,
      spanId: json['spanId']! as String,
    ),
    parentSpanId: json['parentSpanId'] as String?,
    kind: SpanKind.values.byName(json['spanKind']! as String),
    startTime: _dateTimeFromUnixNano(json['startTimeUnixNano']! as String),
    endTime: _dateTimeFromUnixNano(json['endTimeUnixNano']! as String),
    attributes:
        (json['attributes'] as Map?)?.cast<String, Object?>() ?? const {},
    events: eventsJson.cast<Map<String, Object?>>().map((event) {
      return SpanEvent(
        name: event['name']! as String,
        timestamp: _dateTimeFromUnixNano(event['timeUnixNano']! as String),
        attributes:
            (event['attributes'] as Map?)?.cast<String, Object?>() ??
                const {},
      );
    }).toList(),
    statusCode: StatusCode.values.byName(json['statusCode']! as String),
    statusDescription: json['statusDescription'] as String?,
    scopeName:
        json['scopeName'] as String? ?? defaultInstrumentationScopeName,
    scopeVersion: json['scopeVersion'] as String?,
  );
}

LogRecord _decodeLogRecord(Map<String, Object?> json) => LogRecord(
      body: json['body']! as String,
      severity: LogSeverity.values.byName(json['severity']! as String),
      timestamp: _dateTimeFromUnixNano(json['timeUnixNano']! as String),
      attributes:
          (json['attributes'] as Map?)?.cast<String, Object?>() ?? const {},
      traceId: json['traceId'] as String?,
      spanId: json['spanId'] as String?,
    );

DateTime _dateTimeFromUnixNano(String unixNano) =>
    DateTime.fromMicrosecondsSinceEpoch(
      int.parse(unixNano) ~/ 1000,
      isUtc: true,
    );
```

`packages/flutter_otel_native/lib/flutter_otel_native.dart`:

```dart
/// Dart-side bridge to native (iOS/macOS) telemetry recorded via
/// flutter_otel_native's Swift plugin: draining its on-disk queue and
/// forwarding records into an existing TracerProvider/LoggerProvider
/// pipeline, plus trace-context/session handoff primitives.
library;

export 'src/native_record_codec.dart';
```

(Task 4 adds the `native_telemetry_bridge.dart` export to this same file.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/flutter_otel_native && flutter test test/native_record_codec_test.dart`
Expected: PASS

- [ ] **Step 6: Analyze, format, and commit**

Run: `cd packages/flutter_otel_native && flutter analyze && dart format --output=none --set-exit-if-changed .`
Expected: no issues.

```bash
git add pubspec.yaml packages/flutter_otel_native/
git commit -m "feat(otel-native): scaffold flutter_otel_native and add NativeRecordCodec"
```

---

## Task 4: `NativeTelemetryBridge.drainAndForward` + fake providers

**Files:**

- Create: `packages/flutter_otel_native/test/support/fake_tracer_provider.dart`
- Create: `packages/flutter_otel_native/test/support/fake_logger_provider.dart`
- Create: `packages/flutter_otel_native/lib/src/native_telemetry_bridge.dart`
- Modify: `packages/flutter_otel_native/lib/flutter_otel_native.dart`
- Create: `packages/flutter_otel_native/test/native_telemetry_bridge_test.dart`

**Interfaces:**

- Consumes: `decodeNativeRecordLine`, `NativeRecord`, `NativeSpanRecord`, `NativeLogRecord` (Task 3); `TracerProvider.ingestSpan`, `LoggerProvider.ingestLogRecord` (Tasks 1–2).
- Produces: `class NativeDrainResult { int recordsIngested; int recordsSkipped; int recordsDropped; }`, `class NativeTelemetryBridge { NativeTelemetryBridge({MethodChannel? channel}); Future<NativeDrainResult> drainAndForward({required TracerProvider tracerProvider, required LoggerProvider loggerProvider}); }` — the `channel` field/constructor param is reused by Task 5, which adds more methods to this same class.

- [ ] **Step 1: Add fake provider test doubles**

`packages/flutter_otel_native/test/support/fake_tracer_provider.dart`:

```dart
import 'package:flutter_otel_api/flutter_otel_api.dart';

/// A [TracerProvider] test double that records every span passed to
/// [ingestSpan] instead of exporting it anywhere.
class FakeTracerProvider implements TracerProvider {
  final List<SpanData> ingestedSpans = [];

  @override
  void ingestSpan(SpanData span) => ingestedSpans.add(span);

  @override
  Tracer getTracer({String name = 'flutter_otel', String? version}) =>
      NoopTracer(name);

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
```

`packages/flutter_otel_native/test/support/fake_logger_provider.dart`:

```dart
import 'package:flutter_otel_api/flutter_otel_api.dart';

/// A [LoggerProvider] test double that records every record passed to
/// [ingestLogRecord] instead of exporting it anywhere.
class FakeLoggerProvider implements LoggerProvider {
  final List<LogRecord> ingestedRecords = [];

  @override
  void ingestLogRecord(LogRecord record) => ingestedRecords.add(record);

  @override
  Logger getLogger({String name = 'flutter_otel', String? version}) =>
      throw UnimplementedError('not exercised by NativeTelemetryBridge');

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
```

- [ ] **Step 2: Write the failing test for `NativeTelemetryBridge.drainAndForward`**

`packages/flutter_otel_native/test/native_telemetry_bridge_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_otel_native/flutter_otel_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_logger_provider.dart';
import 'support/fake_tracer_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_otel_native');
  late FakeTracerProvider tracerProvider;
  late FakeLoggerProvider loggerProvider;
  late NativeTelemetryBridge bridge;

  setUp(() {
    tracerProvider = FakeTracerProvider();
    loggerProvider = FakeLoggerProvider();
    bridge = NativeTelemetryBridge(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mockDrainResponse(Map<String, Object?> response) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'drainQueue');
      return response;
    });
  }

  test('ingests a mix of decodable span and log lines', () async {
    mockDrainResponse({
      'records': [
        '{"kind":"span","name":"op","traceId":'
            '"4bf92f3577b34da6a3ce929d0e0e4736","spanId":'
            '"00f067aa0ba902b7","parentSpanId":null,"spanKind":"internal",'
            '"startTimeUnixNano":"1700000000000000000","endTimeUnixNano":'
            '"1700000000050000000","attributes":{},"events":[],'
            '"statusCode":"unset","scopeName":"flutter_otel_native"}',
        '{"kind":"log","timeUnixNano":"1700000000010000000","severity":'
            '"info","body":"hi","attributes":{}}',
      ],
      'droppedSinceLastDrain': 0,
    });

    final result = await bridge.drainAndForward(
      tracerProvider: tracerProvider,
      loggerProvider: loggerProvider,
    );

    expect(result.recordsIngested, 2);
    expect(result.recordsSkipped, 0);
    expect(result.recordsDropped, 0);
    expect(tracerProvider.ingestedSpans, hasLength(1));
    expect(loggerProvider.ingestedRecords, hasLength(1));
  });

  test('counts malformed lines as skipped instead of throwing', () async {
    mockDrainResponse({
      'records': ['not json', '{"kind":"metric"}'],
      'droppedSinceLastDrain': 0,
    });

    final result = await bridge.drainAndForward(
      tracerProvider: tracerProvider,
      loggerProvider: loggerProvider,
    );

    expect(result.recordsIngested, 0);
    expect(result.recordsSkipped, 2);
  });

  test('surfaces the native drop count unchanged', () async {
    mockDrainResponse({'records': <String>[], 'droppedSinceLastDrain': 7});

    final result = await bridge.drainAndForward(
      tracerProvider: tracerProvider,
      loggerProvider: loggerProvider,
    );

    expect(result.recordsDropped, 7);
  });

  test('treats a null response as an empty drain', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final result = await bridge.drainAndForward(
      tracerProvider: tracerProvider,
      loggerProvider: loggerProvider,
    );

    expect(result.recordsIngested, 0);
    expect(result.recordsSkipped, 0);
    expect(result.recordsDropped, 0);
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/flutter_otel_native && flutter test test/native_telemetry_bridge_test.dart`
Expected: FAIL — `Target of URI doesn't exist` / `NativeTelemetryBridge` undefined.

- [ ] **Step 4: Implement `NativeTelemetryBridge`**

`packages/flutter_otel_native/lib/src/native_telemetry_bridge.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_otel_api/flutter_otel_api.dart';

import 'native_record_codec.dart';

/// Counts from one [NativeTelemetryBridge.drainAndForward] call.
class NativeDrainResult {
  const NativeDrainResult({
    required this.recordsIngested,
    required this.recordsSkipped,
    required this.recordsDropped,
  });

  /// How many drained lines were successfully decoded and ingested.
  final int recordsIngested;

  /// How many drained lines failed to decode (invalid JSON, unrecognized
  /// `kind`, or a missing required field) and were skipped.
  final int recordsSkipped;

  /// How many records native evicted from its on-disk queue (past its
  /// cap) since the previous drain, as reported by native itself.
  final int recordsDropped;
}

/// Dart-side bridge to `flutter_otel_native`'s Swift plugin: drains its
/// on-disk record queue over a [MethodChannel] and forwards each decoded
/// record into an existing [TracerProvider]/[LoggerProvider] pipeline.
class NativeTelemetryBridge {
  NativeTelemetryBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('flutter_otel_native');

  final MethodChannel _channel;

  /// Drains the native queue and forwards every decodable record into
  /// [tracerProvider]/[loggerProvider]. Never throws on malformed native
  /// data — malformed lines are counted in the result instead.
  Future<NativeDrainResult> drainAndForward({
    required TracerProvider tracerProvider,
    required LoggerProvider loggerProvider,
  }) async {
    final response =
        await _channel.invokeMapMethod<String, Object?>('drainQueue');
    final lines =
        (response?['records'] as List?)?.cast<String>() ?? const <String>[];
    final dropped = response?['droppedSinceLastDrain'] as int? ?? 0;

    var ingested = 0;
    var skipped = 0;
    for (final line in lines) {
      switch (decodeNativeRecordLine(line)) {
        case NativeSpanRecord(:final spanData):
          tracerProvider.ingestSpan(spanData);
          ingested++;
        case NativeLogRecord(:final logRecord):
          loggerProvider.ingestLogRecord(logRecord);
          ingested++;
        case null:
          skipped++;
      }
    }

    return NativeDrainResult(
      recordsIngested: ingested,
      recordsSkipped: skipped,
      recordsDropped: dropped,
    );
  }
}
```

Update `packages/flutter_otel_native/lib/flutter_otel_native.dart` to also export it:

```dart
library;

export 'src/native_record_codec.dart';
export 'src/native_telemetry_bridge.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/flutter_otel_native && flutter test test/native_telemetry_bridge_test.dart`
Expected: PASS

- [ ] **Step 6: Analyze, format, and commit**

Run: `cd packages/flutter_otel_native && flutter analyze && dart format --output=none --set-exit-if-changed .`
Expected: no issues.

```bash
git add packages/flutter_otel_native/
git commit -m "feat(otel-native): add NativeTelemetryBridge.drainAndForward"
```

---

## Task 5: `NativeTelemetryBridge` session + trace-context primitives

**Files:**

- Modify: `packages/flutter_otel_native/lib/src/native_telemetry_bridge.dart`
- Modify: `packages/flutter_otel_native/test/native_telemetry_bridge_test.dart`

**Interfaces:**

- Consumes: `SpanContext` (`flutter_otel_api`, already exists).
- Produces: `NativeTelemetryBridge.setSessionId(String sessionId)`, `NativeTelemetryBridge.setCurrentTraceContext(SpanContext context)`, `NativeTelemetryBridge.clearCurrentTraceContext()` — these invoke channel methods `'setSessionId'`, `'setCurrentTraceContext'`, `'clearCurrentTraceContext'`, matched by the Swift plugin implemented in Task 9.

- [ ] **Step 1: Write the failing tests**

Add to `packages/flutter_otel_native/test/native_telemetry_bridge_test.dart`, a new top-level test group (needs `import 'package:flutter_otel_api/flutter_otel_api.dart';` added at the top for `SpanContext`):

```dart
  group('session and trace-context primitives', () {
    test('setSessionId invokes the channel with the session id', () async {
      MethodCall? invoked;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        invoked = call;
        return null;
      });

      await bridge.setSessionId('session-123');

      expect(invoked?.method, 'setSessionId');
      expect(invoked?.arguments, {'sessionId': 'session-123'});
    });

    test('setCurrentTraceContext invokes the channel with traceId/spanId',
        () async {
      MethodCall? invoked;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        invoked = call;
        return null;
      });

      await bridge.setCurrentTraceContext(const SpanContext(
        traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
        spanId: '00f067aa0ba902b7',
      ));

      expect(invoked?.method, 'setCurrentTraceContext');
      expect(invoked?.arguments, {
        'traceId': '4bf92f3577b34da6a3ce929d0e0e4736',
        'spanId': '00f067aa0ba902b7',
      });
    });

    test('clearCurrentTraceContext invokes the channel with no arguments',
        () async {
      MethodCall? invoked;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        invoked = call;
        return null;
      });

      await bridge.clearCurrentTraceContext();

      expect(invoked?.method, 'clearCurrentTraceContext');
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/flutter_otel_native && flutter test test/native_telemetry_bridge_test.dart`
Expected: FAIL — `The method 'setSessionId' isn't defined for the type 'NativeTelemetryBridge'` (and similarly for the other two).

- [ ] **Step 3: Implement the three methods**

In `packages/flutter_otel_native/lib/src/native_telemetry_bridge.dart`, add inside the `NativeTelemetryBridge` class, after `drainAndForward`:

```dart
  /// Tags subsequent native records with [sessionId] as a `session.id`
  /// attribute. Call once at startup and again whenever the session rolls.
  Future<void> setSessionId(String sessionId) =>
      _channel.invokeMethod('setSessionId', {'sessionId': sessionId});

  /// Tells native the currently active trace/span, so a native record
  /// taken moments later attaches as its child by default instead of
  /// starting a new root.
  Future<void> setCurrentTraceContext(SpanContext context) =>
      _channel.invokeMethod('setCurrentTraceContext', {
        'traceId': context.traceId,
        'spanId': context.spanId,
      });

  /// Clears whatever [setCurrentTraceContext] last set.
  Future<void> clearCurrentTraceContext() =>
      _channel.invokeMethod('clearCurrentTraceContext');
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/flutter_otel_native && flutter test test/native_telemetry_bridge_test.dart`
Expected: PASS

- [ ] **Step 5: Analyze, format, and commit**

Run: `cd packages/flutter_otel_native && flutter analyze && dart format --output=none --set-exit-if-changed .`
Expected: no issues.

```bash
git add packages/flutter_otel_native/
git commit -m "feat(otel-native): add session and trace-context bridge primitives"
```

---

## Task 6: `NativeTelemetryCore` Swift package + ID generation

**Files:**

- Create: `packages/flutter_otel_native/native/NativeTelemetryCore/Package.swift`
- Create: `packages/flutter_otel_native/native/NativeTelemetryCore/Sources/NativeTelemetryCore/NativeId.swift`
- Create: `packages/flutter_otel_native/native/NativeTelemetryCore/Tests/NativeTelemetryCoreTests/NativeIdTests.swift`

**Interfaces:**

- Produces: `public enum NativeId { public static func generateTraceId() -> String; public static func generateSpanId() -> String }` — used by `NativeTelemetryRecorder` in Task 8.

This is a standalone Swift package with **no Flutter dependency at all** — it only imports `Foundation` (and `Security` on Darwin). That's what makes it testable with a plain `swift test`, independent of the Flutter/Xcode plugin build that Task 9 wires up.

- [ ] **Step 1: Create the package manifest**

`packages/flutter_otel_native/native/NativeTelemetryCore/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NativeTelemetryCore",
    platforms: [
        .iOS("15.0"),
        .macOS("12.0"),
    ],
    products: [
        .library(name: "NativeTelemetryCore", targets: ["NativeTelemetryCore"])
    ],
    targets: [
        .target(name: "NativeTelemetryCore"),
        .testTarget(
            name: "NativeTelemetryCoreTests",
            dependencies: ["NativeTelemetryCore"]
        ),
    ]
)
```

- [ ] **Step 2: Write the failing test**

`packages/flutter_otel_native/native/NativeTelemetryCore/Tests/NativeTelemetryCoreTests/NativeIdTests.swift`:

```swift
import XCTest
@testable import NativeTelemetryCore

final class NativeIdTests: XCTestCase {
    func testTraceIdIsThirtyTwoLowercaseHexCharacters() {
        let traceId = NativeId.generateTraceId()

        XCTAssertEqual(traceId.count, 32)
        XCTAssertNotNil(traceId.range(of: "^[0-9a-f]{32}$", options: .regularExpression))
    }

    func testSpanIdIsSixteenLowercaseHexCharacters() {
        let spanId = NativeId.generateSpanId()

        XCTAssertEqual(spanId.count, 16)
        XCTAssertNotNil(spanId.range(of: "^[0-9a-f]{16}$", options: .regularExpression))
    }

    func testGeneratesDistinctIdsAcrossCalls() {
        let first = NativeId.generateTraceId()
        let second = NativeId.generateTraceId()

        XCTAssertNotEqual(first, second)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd packages/flutter_otel_native/native/NativeTelemetryCore && swift test`
Expected: FAIL to build — `cannot find 'NativeId' in scope`.

- [ ] **Step 4: Implement `NativeId`**

`packages/flutter_otel_native/native/NativeTelemetryCore/Sources/NativeTelemetryCore/NativeId.swift`:

```swift
import Foundation
#if canImport(Security)
import Security
#endif

/// Generates W3C-Trace-Context-conformant IDs: a 32-lowercase-hex-character
/// trace ID (16 random bytes) and a 16-lowercase-hex-character span ID (8
/// random bytes) — exactly the format `SpanContext` on the Dart side
/// already validates, so no coordination between the two sides is needed.
public enum NativeId {
    public static func generateTraceId() -> String { hexString(byteCount: 16) }

    public static func generateSpanId() -> String { hexString(byteCount: 8) }

    private static func hexString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        #if canImport(Security)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            for i in 0..<byteCount { bytes[i] = UInt8.random(in: 0...255) }
        }
        #else
        for i in 0..<byteCount { bytes[i] = UInt8.random(in: 0...255) }
        #endif
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/flutter_otel_native/native/NativeTelemetryCore && swift test`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add packages/flutter_otel_native/native/
git commit -m "feat(otel-native): add NativeTelemetryCore Swift package with NativeId"
```

---

## Task 7: `RecordQueue` (Swift)

**Files:**

- Create: `packages/flutter_otel_native/native/NativeTelemetryCore/Sources/NativeTelemetryCore/RecordQueue.swift`
- Create: `packages/flutter_otel_native/native/NativeTelemetryCore/Tests/NativeTelemetryCoreTests/RecordQueueTests.swift`

**Interfaces:**

- Produces: `public final class RecordQueue { public struct DrainResult { public let lines: [String]; public let droppedSinceLastDrain: Int }; public init(fileURL: URL, maxRecords: Int = 2048); public func append(_ record: [String: Any]); public func drain() -> DrainResult }` — used by `NativeTelemetryRecorder` in Task 8.

**Known simplification (see Global Constraints):** `append` and `drain` each read and rewrite the whole queue file rather than doing a true streaming append; this is simple and correct, and the expected record volumes (a handful of native events per app run, capped at 2048) make the inefficiency immaterial for this foundation. Revisit only if profiling in a later spec shows it matters.

- [ ] **Step 1: Write the failing tests**

`packages/flutter_otel_native/native/NativeTelemetryCore/Tests/NativeTelemetryCoreTests/RecordQueueTests.swift`:

```swift
import XCTest
@testable import NativeTelemetryCore

final class RecordQueueTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("record_queue_test_\(UUID().uuidString).ndjson")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    func testDrainReturnsAppendedRecordsAndClearsTheFile() {
        let queue = RecordQueue(fileURL: fileURL, maxRecords: 10)
        queue.append(["kind": "log", "body": "one"])
        queue.append(["kind": "log", "body": "two"])

        let result = queue.drain()

        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.droppedSinceLastDrain, 0)
        XCTAssertTrue(queue.drain().lines.isEmpty)
    }

    func testEvictsOldestRecordsPastTheCapAndReportsTheDropCount() {
        let queue = RecordQueue(fileURL: fileURL, maxRecords: 2)
        queue.append(["kind": "log", "body": "one"])
        queue.append(["kind": "log", "body": "two"])
        queue.append(["kind": "log", "body": "three"])

        let result = queue.drain()

        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.droppedSinceLastDrain, 1)
        XCTAssertFalse(result.lines.contains { $0.contains("\"one\"") })
    }

    func testSkipsRecordsThatArentValidJSONObjectsWithoutCrashing() {
        let queue = RecordQueue(fileURL: fileURL, maxRecords: 10)
        queue.append(["kind": "log", "body": "ok"])
        // NaN has no JSON representation; JSONSerialization rejects it, so
        // this append should be silently dropped rather than throwing.
        queue.append(["kind": "log", "value": Double.nan])

        let result = queue.drain()

        XCTAssertEqual(result.lines.count, 1)
    }

    func testDropCounterResetsAfterEachDrain() {
        let queue = RecordQueue(fileURL: fileURL, maxRecords: 1)
        queue.append(["kind": "log", "body": "one"])
        queue.append(["kind": "log", "body": "two"])
        _ = queue.drain()

        queue.append(["kind": "log", "body": "three"])
        let result = queue.drain()

        XCTAssertEqual(result.droppedSinceLastDrain, 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/flutter_otel_native/native/NativeTelemetryCore && swift test`
Expected: FAIL to build — `cannot find 'RecordQueue' in scope`.

- [ ] **Step 3: Implement `RecordQueue`**

`packages/flutter_otel_native/native/NativeTelemetryCore/Sources/NativeTelemetryCore/RecordQueue.swift`:

```swift
import Foundation

/// Appends telemetry records as NDJSON lines to an on-disk queue file and
/// performs an atomic drain-and-clear, all serialized on one internal
/// dispatch queue so it's safe to call from any thread.
public final class RecordQueue {
    public struct DrainResult {
        public let lines: [String]
        public let droppedSinceLastDrain: Int
    }

    private let fileURL: URL
    private let maxRecords: Int
    private let ioQueue = DispatchQueue(label: "flutter_otel_native.record_queue")
    private var droppedSinceLastDrain = 0

    public init(fileURL: URL, maxRecords: Int = 2048) {
        self.fileURL = fileURL
        self.maxRecords = maxRecords
    }

    /// Appends [record] to the queue. Silently drops it (never throws) if
    /// it isn't a valid JSON object — a caller bug in a future
    /// instrumentation spec shouldn't be able to crash the app.
    public func append(_ record: [String: Any]) {
        ioQueue.sync {
            guard JSONSerialization.isValidJSONObject(record),
                  let data = try? JSONSerialization.data(withJSONObject: record),
                  let line = String(data: data, encoding: .utf8) else {
                return
            }

            var lines = readLinesLocked()
            lines.append(line)
            if lines.count > maxRecords {
                let overflow = lines.count - maxRecords
                lines.removeFirst(overflow)
                droppedSinceLastDrain += overflow
            }
            writeLinesLocked(lines)
        }
    }

    /// Returns every queued line and the drop count since the previous
    /// drain, then clears both.
    public func drain() -> DrainResult {
        ioQueue.sync {
            let lines = readLinesLocked()
            writeLinesLocked([])
            let dropped = droppedSinceLastDrain
            droppedSinceLastDrain = 0
            return DrainResult(lines: lines, droppedSinceLastDrain: dropped)
        }
    }

    private func readLinesLocked() -> [String] {
        guard let data = try? Data(contentsOf: fileURL),
              let contents = String(data: data, encoding: .utf8),
              !contents.isEmpty else {
            return []
        }
        return contents.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private func writeLinesLocked(_ lines: [String]) {
        let contents = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/flutter_otel_native/native/NativeTelemetryCore && swift test`
Expected: PASS (7 tests total, including Task 6's)

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_otel_native/native/
git commit -m "feat(otel-native): add RecordQueue with a capped, drainable NDJSON file"
```

---

## Task 8: `NativeTelemetryRecorder` (Swift)

**Files:**

- Create: `packages/flutter_otel_native/native/NativeTelemetryCore/Sources/NativeTelemetryCore/NativeTelemetryRecorder.swift`
- Create: `packages/flutter_otel_native/native/NativeTelemetryCore/Tests/NativeTelemetryCoreTests/NativeTelemetryRecorderTests.swift`

**Interfaces:**

- Consumes: `NativeId` (Task 6), `RecordQueue` (Task 7).
- Produces: `public final class NativeTelemetryRecorder` with `init(queue: RecordQueue)`, `setTraceContext(traceId:spanId:)`, `clearTraceContext()`, `setSessionId(_:)`, `recordSpan(name:kind:start:end:attributes:events:statusCode:statusDescription:traceId:spanId:parentSpanId:) -> (traceId: String, spanId: String)`, `recordLog(body:severity:timestamp:attributes:)`, `drainQueue() -> RecordQueue.DrainResult`, plus the supporting types `NativeRecordEvent`, `NativeSpanKind`, `NativeStatusCode`, `NativeLogSeverity` — all consumed by the `FlutterOtelNativePlugin` implementations in Task 9. The wire format this produces must match the Global Constraints JSON schema exactly, since Task 3/4's Dart decoder was written against it.

- [ ] **Step 1: Write the failing tests**

`packages/flutter_otel_native/native/NativeTelemetryCore/Tests/NativeTelemetryCoreTests/NativeTelemetryRecorderTests.swift`:

```swift
import XCTest
@testable import NativeTelemetryCore

final class NativeTelemetryRecorderTests: XCTestCase {
    private var fileURL: URL!
    private var queue: RecordQueue!
    private var recorder: NativeTelemetryRecorder!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder_test_\(UUID().uuidString).ndjson")
        queue = RecordQueue(fileURL: fileURL, maxRecords: 10)
        recorder = NativeTelemetryRecorder(queue: queue)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    private func decodeLastRecord() throws -> [String: Any] {
        let result = queue.drain()
        let line = try XCTUnwrap(result.lines.last)
        let data = try XCTUnwrap(line.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testRecordSpanWithNoContextGeneratesARootTraceAndSpanId() throws {
        let ids = recorder.recordSpan(name: "op", start: Date(), end: Date())

        XCTAssertEqual(ids.traceId.count, 32)
        XCTAssertEqual(ids.spanId.count, 16)

        let json = try decodeLastRecord()
        XCTAssertEqual(json["kind"] as? String, "span")
        XCTAssertEqual(json["name"] as? String, "op")
        XCTAssertEqual(json["traceId"] as? String, ids.traceId)
        XCTAssertEqual(json["spanId"] as? String, ids.spanId)
        XCTAssertNil(json["parentSpanId"])
        XCTAssertEqual(json["spanKind"] as? String, "internal")
        XCTAssertEqual(json["statusCode"] as? String, "unset")
        XCTAssertEqual(json["scopeName"] as? String, "flutter_otel_native")
    }

    func testRecordSpanAttachesAsAChildWhenTraceContextIsSet() throws {
        recorder.setTraceContext(traceId: "4bf92f3577b34da6a3ce929d0e0e4736", spanId: "00f067aa0ba902b7")

        let ids = recorder.recordSpan(name: "op", start: Date(), end: Date())

        XCTAssertEqual(ids.traceId, "4bf92f3577b34da6a3ce929d0e0e4736")
        XCTAssertNotEqual(ids.spanId, "00f067aa0ba902b7")

        let json = try decodeLastRecord()
        XCTAssertEqual(json["parentSpanId"] as? String, "00f067aa0ba902b7")
    }

    func testClearTraceContextStopsFurtherChildAttachment() throws {
        recorder.setTraceContext(traceId: "4bf92f3577b34da6a3ce929d0e0e4736", spanId: "00f067aa0ba902b7")
        recorder.clearTraceContext()

        let ids = recorder.recordSpan(name: "op", start: Date(), end: Date())

        XCTAssertNotEqual(ids.traceId, "4bf92f3577b34da6a3ce929d0e0e4736")
        let json = try decodeLastRecord()
        XCTAssertNil(json["parentSpanId"])
    }

    func testExplicitIdsOverrideInheritedContext() throws {
        recorder.setTraceContext(traceId: "4bf92f3577b34da6a3ce929d0e0e4736", spanId: "00f067aa0ba902b7")

        let ids = recorder.recordSpan(
            name: "op",
            start: Date(),
            end: Date(),
            traceId: "11111111111111111111111111111111",
            spanId: "2222222222222222"
        )

        XCTAssertEqual(ids.traceId, "11111111111111111111111111111111")
        XCTAssertEqual(ids.spanId, "2222222222222222")
        let json = try decodeLastRecord()
        XCTAssertNil(json["parentSpanId"])
    }

    func testRecordSpanEncodesEventsAndStatus() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(0.05)
        let event = NativeRecordEvent(name: "retry", timestamp: start, attributes: ["attempt": 1])

        _ = recorder.recordSpan(
            name: "op",
            kind: .client,
            start: start,
            end: end,
            attributes: ["http.method": "GET"],
            events: [event],
            statusCode: .error,
            statusDescription: "timed out"
        )

        let json = try decodeLastRecord()
        XCTAssertEqual(json["spanKind"] as? String, "client")
        XCTAssertEqual(json["statusCode"] as? String, "error")
        XCTAssertEqual(json["statusDescription"] as? String, "timed out")
        let attributes = try XCTUnwrap(json["attributes"] as? [String: Any])
        XCTAssertEqual(attributes["http.method"] as? String, "GET")
        let events = try XCTUnwrap(json["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["name"] as? String, "retry")
    }

    func testRecordLogMergesSessionIdWhenSet() throws {
        recorder.setSessionId("session-123")

        recorder.recordLog(body: "hello")

        let json = try decodeLastRecord()
        XCTAssertEqual(json["kind"] as? String, "log")
        XCTAssertEqual(json["body"] as? String, "hello")
        let attributes = try XCTUnwrap(json["attributes"] as? [String: Any])
        XCTAssertEqual(attributes["session.id"] as? String, "session-123")
    }

    func testRecordLogCarriesTheActiveTraceContext() throws {
        recorder.setTraceContext(traceId: "4bf92f3577b34da6a3ce929d0e0e4736", spanId: "00f067aa0ba902b7")

        recorder.recordLog(body: "hello")

        let json = try decodeLastRecord()
        XCTAssertEqual(json["traceId"] as? String, "4bf92f3577b34da6a3ce929d0e0e4736")
        XCTAssertEqual(json["spanId"] as? String, "00f067aa0ba902b7")
    }

    func testRecordLogWithNoContextOmitsTraceFields() throws {
        recorder.recordLog(body: "hello")

        let json = try decodeLastRecord()
        XCTAssertNil(json["traceId"])
        XCTAssertNil(json["spanId"])
    }

    func testDrainQueuePassesThroughToTheUnderlyingQueue() {
        recorder.recordLog(body: "hello")

        let result = recorder.drainQueue()

        XCTAssertEqual(result.lines.count, 1)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/flutter_otel_native/native/NativeTelemetryCore && swift test`
Expected: FAIL to build — `cannot find 'NativeTelemetryRecorder' in scope`.

- [ ] **Step 3: Implement `NativeTelemetryRecorder`**

`packages/flutter_otel_native/native/NativeTelemetryCore/Sources/NativeTelemetryCore/NativeTelemetryRecorder.swift`:

```swift
import Foundation

public struct NativeRecordEvent {
    public let name: String
    public let timestamp: Date
    public let attributes: [String: Any]

    public init(name: String, timestamp: Date, attributes: [String: Any] = [:]) {
        self.name = name
        self.timestamp = timestamp
        self.attributes = attributes
    }
}

public enum NativeSpanKind: String {
    case internalKind = "internal"
    case server
    case client
    case producer
    case consumer
}

public enum NativeStatusCode: String {
    case unset
    case ok
    case error
}

public enum NativeLogSeverity: String {
    case trace
    case debug
    case info
    case warn
    case error
    case fatal
}

/// The only entry point native instrumentation (cold-start, crash capture,
/// background tasks, native networking — none implemented yet) will call
/// to record a finished span or log record. Defaults a new record's trace
/// context onto whatever [setTraceContext] last set, and tags it with
/// whatever [setSessionId] last set, unless the caller passes explicit
/// IDs/attributes.
public final class NativeTelemetryRecorder {
    private let queue: RecordQueue
    private let lock = NSLock()
    private var currentTraceId: String?
    private var currentSpanId: String?
    private var currentSessionId: String?

    public init(queue: RecordQueue) {
        self.queue = queue
    }

    public func setTraceContext(traceId: String, spanId: String) {
        lock.lock(); defer { lock.unlock() }
        currentTraceId = traceId
        currentSpanId = spanId
    }

    public func clearTraceContext() {
        lock.lock(); defer { lock.unlock() }
        currentTraceId = nil
        currentSpanId = nil
    }

    public func setSessionId(_ sessionId: String) {
        lock.lock(); defer { lock.unlock() }
        currentSessionId = sessionId
    }

    public func drainQueue() -> RecordQueue.DrainResult {
        queue.drain()
    }

    @discardableResult
    public func recordSpan(
        name: String,
        kind: NativeSpanKind = .internalKind,
        start: Date,
        end: Date,
        attributes: [String: Any] = [:],
        events: [NativeRecordEvent] = [],
        statusCode: NativeStatusCode = .unset,
        statusDescription: String? = nil,
        traceId explicitTraceId: String? = nil,
        spanId explicitSpanId: String? = nil,
        parentSpanId explicitParentSpanId: String? = nil
    ) -> (traceId: String, spanId: String) {
        lock.lock()
        let inheritedTraceId = currentTraceId
        let inheritedSpanId = currentSpanId
        let sessionId = currentSessionId
        lock.unlock()

        let traceId = explicitTraceId ?? inheritedTraceId ?? NativeId.generateTraceId()
        let spanId = explicitSpanId ?? NativeId.generateSpanId()
        let parentSpanId = explicitParentSpanId
            ?? (explicitTraceId == nil ? inheritedSpanId : nil)

        var mergedAttributes = attributes
        if let sessionId = sessionId, mergedAttributes["session.id"] == nil {
            mergedAttributes["session.id"] = sessionId
        }

        var record: [String: Any] = [
            "kind": "span",
            "name": name,
            "traceId": traceId,
            "spanId": spanId,
            "spanKind": kind.rawValue,
            "startTimeUnixNano": String(unixNano(start)),
            "endTimeUnixNano": String(unixNano(end)),
            "attributes": mergedAttributes,
            "events": events.map { event -> [String: Any] in
                [
                    "name": event.name,
                    "timeUnixNano": String(unixNano(event.timestamp)),
                    "attributes": event.attributes,
                ]
            },
            "statusCode": statusCode.rawValue,
            "scopeName": "flutter_otel_native",
            "scopeVersion": "0.1.0",
        ]
        if let parentSpanId = parentSpanId {
            record["parentSpanId"] = parentSpanId
        }
        if let statusDescription = statusDescription {
            record["statusDescription"] = statusDescription
        }

        queue.append(record)
        return (traceId, spanId)
    }

    public func recordLog(
        body: String,
        severity: NativeLogSeverity = .info,
        timestamp: Date = Date(),
        attributes: [String: Any] = [:]
    ) {
        lock.lock()
        let traceId = currentTraceId
        let spanId = currentSpanId
        let sessionId = currentSessionId
        lock.unlock()

        var mergedAttributes = attributes
        if let sessionId = sessionId, mergedAttributes["session.id"] == nil {
            mergedAttributes["session.id"] = sessionId
        }

        var record: [String: Any] = [
            "kind": "log",
            "timeUnixNano": String(unixNano(timestamp)),
            "severity": severity.rawValue,
            "body": body,
            "attributes": mergedAttributes,
        ]
        if let traceId = traceId { record["traceId"] = traceId }
        if let spanId = spanId { record["spanId"] = spanId }

        queue.append(record)
    }

    private func unixNano(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000_000_000)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/flutter_otel_native/native/NativeTelemetryCore && swift test`
Expected: PASS (16 tests total)

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_otel_native/native/
git commit -m "feat(otel-native): add NativeTelemetryRecorder with trace/session default-attach"
```

---

## Task 9: Wire the Flutter plugin (iOS + macOS)

**Files:**

- Create: `packages/flutter_otel_native/ios/flutter_otel_native.podspec`
- Create: `packages/flutter_otel_native/ios/flutter_otel_native/Package.swift`
- Create: `packages/flutter_otel_native/ios/flutter_otel_native/Sources/flutter_otel_native/FlutterOtelNativePlugin.swift`
- Create: `packages/flutter_otel_native/macos/flutter_otel_native.podspec`
- Create: `packages/flutter_otel_native/macos/flutter_otel_native/Package.swift`
- Create: `packages/flutter_otel_native/macos/flutter_otel_native/Sources/flutter_otel_native/FlutterOtelNativePlugin.swift`

**Interfaces:**

- Consumes: `NativeTelemetryRecorder`, `RecordQueue` (Task 8, via the `NativeTelemetryCore` product).
- Produces: a registered `FlutterPlugin` per platform handling channel methods `drainQueue`, `setSessionId`, `setCurrentTraceContext`, `clearCurrentTraceContext` — matching exactly what `NativeTelemetryBridge` (Tasks 4–5) sends.

This task has no automated test of its own: `FlutterOtelNativePlugin` can't be unit-tested with plain XCTest (it needs a real `Flutter`/`FlutterMacOS` framework and plugin registrar, which only exist inside a built Flutter app). Task 10's example-app build is what actually exercises this code end-to-end; this task's own verification is limited to `swift`/CocoaPods syntax sanity (below).

- [ ] **Step 1: iOS podspec**

`packages/flutter_otel_native/ios/flutter_otel_native.podspec`:

```ruby
Pod::Spec.new do |s|
  s.name             = 'flutter_otel_native'
  s.version          = '0.1.0'
  s.summary          = 'Native (Swift) telemetry foundation for flutter_otel.'
  s.description      = <<-DESC
On-disk span/log queue and MethodChannel bridge that let native iOS code
record telemetry before or without a running Dart isolate, forwarded into
flutter_otel's existing OTLP export pipeline.
                       DESC
  s.homepage         = 'https://github.com/cedricziel/flutter-otel'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Cedric Ziel' => 'cedric.ziel@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_otel_native/Sources/flutter_otel_native/**/*',
                    '../native/NativeTelemetryCore/Sources/NativeTelemetryCore/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'
end
```

- [ ] **Step 2: iOS SPM package**

`packages/flutter_otel_native/ios/flutter_otel_native/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_otel_native",
    platforms: [.iOS("15.0")],
    products: [
        .library(name: "flutter-otel-native", targets: ["flutter_otel_native"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(path: "../../native/NativeTelemetryCore"),
    ],
    targets: [
        .target(
            name: "flutter_otel_native",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "NativeTelemetryCore", package: "NativeTelemetryCore"),
            ]
        )
    ]
)
```

- [ ] **Step 3: iOS plugin class**

`packages/flutter_otel_native/ios/flutter_otel_native/Sources/flutter_otel_native/FlutterOtelNativePlugin.swift`:

```swift
import Flutter
import NativeTelemetryCore

public class FlutterOtelNativePlugin: NSObject, FlutterPlugin {
    private let recorder: NativeTelemetryRecorder

    public override init() {
        let directory = FlutterOtelNativePlugin.queueDirectory()
        let queue = RecordQueue(fileURL: directory.appendingPathComponent("flutter_otel_native_queue.ndjson"))
        recorder = NativeTelemetryRecorder(queue: queue)
        super.init()
    }

    private static func queueDirectory() -> URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_otel_native", binaryMessenger: registrar.messenger())
        let instance = FlutterOtelNativePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "drainQueue":
            let drainResult = recorder.drainQueue()
            result([
                "records": drainResult.lines,
                "droppedSinceLastDrain": drainResult.droppedSinceLastDrain,
            ])
        case "setSessionId":
            guard let args = call.arguments as? [String: Any],
                  let sessionId = args["sessionId"] as? String else {
                result(FlutterError(code: "invalid_arguments", message: "sessionId is required", details: nil))
                return
            }
            recorder.setSessionId(sessionId)
            result(nil)
        case "setCurrentTraceContext":
            guard let args = call.arguments as? [String: Any],
                  let traceId = args["traceId"] as? String,
                  let spanId = args["spanId"] as? String else {
                result(FlutterError(code: "invalid_arguments", message: "traceId and spanId are required", details: nil))
                return
            }
            recorder.setTraceContext(traceId: traceId, spanId: spanId)
            result(nil)
        case "clearCurrentTraceContext":
            recorder.clearTraceContext()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
```

- [ ] **Step 4: macOS podspec**

`packages/flutter_otel_native/macos/flutter_otel_native.podspec`:

```ruby
Pod::Spec.new do |s|
  s.name             = 'flutter_otel_native'
  s.version          = '0.1.0'
  s.summary          = 'Native (Swift) telemetry foundation for flutter_otel.'
  s.description      = <<-DESC
On-disk span/log queue and MethodChannel bridge that let native macOS code
record telemetry before or without a running Dart isolate, forwarded into
flutter_otel's existing OTLP export pipeline.
                       DESC
  s.homepage         = 'https://github.com/cedricziel/flutter-otel'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Cedric Ziel' => 'cedric.ziel@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_otel_native/Sources/flutter_otel_native/**/*',
                    '../native/NativeTelemetryCore/Sources/NativeTelemetryCore/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
```

- [ ] **Step 5: macOS SPM package**

`packages/flutter_otel_native/macos/flutter_otel_native/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_otel_native",
    platforms: [.macOS("12.0")],
    products: [
        .library(name: "flutter-otel-native", targets: ["flutter_otel_native"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(path: "../../native/NativeTelemetryCore"),
    ],
    targets: [
        .target(
            name: "flutter_otel_native",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "NativeTelemetryCore", package: "NativeTelemetryCore"),
            ]
        )
    ]
)
```

- [ ] **Step 6: macOS plugin class**

`packages/flutter_otel_native/macos/flutter_otel_native/Sources/flutter_otel_native/FlutterOtelNativePlugin.swift`:

```swift
import FlutterMacOS
import NativeTelemetryCore

public class FlutterOtelNativePlugin: NSObject, FlutterPlugin {
    private let recorder: NativeTelemetryRecorder

    public override init() {
        let directory = FlutterOtelNativePlugin.queueDirectory()
        let queue = RecordQueue(fileURL: directory.appendingPathComponent("flutter_otel_native_queue.ndjson"))
        recorder = NativeTelemetryRecorder(queue: queue)
        super.init()
    }

    private static func queueDirectory() -> URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_otel_native", binaryMessenger: registrar.messenger)
        let instance = FlutterOtelNativePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "drainQueue":
            let drainResult = recorder.drainQueue()
            result([
                "records": drainResult.lines,
                "droppedSinceLastDrain": drainResult.droppedSinceLastDrain,
            ])
        case "setSessionId":
            guard let args = call.arguments as? [String: Any],
                  let sessionId = args["sessionId"] as? String else {
                result(FlutterError(code: "invalid_arguments", message: "sessionId is required", details: nil))
                return
            }
            recorder.setSessionId(sessionId)
            result(nil)
        case "setCurrentTraceContext":
            guard let args = call.arguments as? [String: Any],
                  let traceId = args["traceId"] as? String,
                  let spanId = args["spanId"] as? String else {
                result(FlutterError(code: "invalid_arguments", message: "traceId and spanId are required", details: nil))
                return
            }
            recorder.setTraceContext(traceId: traceId, spanId: spanId)
            result(nil)
        case "clearCurrentTraceContext":
            recorder.clearTraceContext()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
```

- [ ] **Step 7: Commit**

```bash
git add packages/flutter_otel_native/ios packages/flutter_otel_native/macos
git commit -m "feat(otel-native): wire the iOS and macOS Flutter plugin implementations"
```

---

## Task 10: Example app smoke build

**Files:**

- Create: `packages/flutter_otel_native/example/pubspec.yaml`
- Create: `packages/flutter_otel_native/example/lib/main.dart`
- Create: `packages/flutter_otel_native/example/ios/...` and `packages/flutter_otel_native/example/macos/...` — generated, see Step 1.

**Interfaces:**

- Consumes: `NativeTelemetryBridge`, `NativeDrainResult` (Task 4/5); `TracerProvider`, `LoggerProvider`, `SpanData`, `LogRecord`, `NoopTracer` (`flutter_otel_api`).

This is the first point in the plan where the whole stack — Dart bridge, `MethodChannel`, registered `FlutterPlugin`, `NativeTelemetryCore` compiled via CocoaPods — actually has to build and run together, so it is the closest thing this plan has to an end-to-end check for Task 9.

- [ ] **Step 1: Generate the example app's iOS/macOS host projects**

Run this once, from `packages/flutter_otel_native`, to generate `example/ios/` and `example/macos/` (the Xcode host projects) without touching the `lib/`, `ios/`, or `macos/` plugin files already created in earlier tasks:

```bash
cd packages/flutter_otel_native
flutter create --template=plugin --platforms=ios,macos --org com.cedricziel --project-name flutter_otel_native .
```

(Flutter's `create` command on an existing plugin directory only fills in missing scaffold files — such as `example/` — without overwriting the plugin's own `lib/`, `ios/`, `macos/`, or `pubspec.yaml` content from earlier tasks; if the tool prompts to overwrite anything under those directories, answer no and cross-check that the file in question really does already match this plan.)

- [ ] **Step 2: Replace the generated example pubspec's plugin dependency section**

Open `packages/flutter_otel_native/example/pubspec.yaml`. Under `dependencies:`, replace whatever it generated for `flutter_otel_native` and add `flutter_otel_api` as a sibling path dependency (the example isn't a pub workspace member, so it resolves independently, like any plugin's own example app):

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_otel_native:
    path: ../
  flutter_otel_api:
    path: ../../flutter_otel_api
```

Leave the rest of the generated file (the `dev_dependencies`, `flutter:` section) as-is.

- [ ] **Step 3: Replace the generated example app**

`packages/flutter_otel_native/example/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:flutter_otel_native/flutter_otel_native.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _bridge = NativeTelemetryBridge();
  String _status = 'Draining native queue...';

  @override
  void initState() {
    super.initState();
    _drain();
  }

  Future<void> _drain() async {
    final result = await _bridge.drainAndForward(
      tracerProvider: _CountingTracerProvider(),
      loggerProvider: _CountingLoggerProvider(),
    );
    if (!mounted) return;
    setState(() {
      _status = 'ingested: ${result.recordsIngested}, '
          'skipped: ${result.recordsSkipped}, '
          'dropped: ${result.recordsDropped}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_otel_native example')),
        body: Center(child: Text(_status)),
      ),
    );
  }
}

class _CountingTracerProvider implements TracerProvider {
  @override
  void ingestSpan(SpanData span) {}

  @override
  Tracer getTracer({String name = 'flutter_otel', String? version}) =>
      const NoopTracer('example');

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

class _CountingLoggerProvider implements LoggerProvider {
  @override
  void ingestLogRecord(LogRecord record) {}

  @override
  Logger getLogger({String name = 'flutter_otel', String? version}) =>
      throw UnimplementedError('not exercised by this example');

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
```

- [ ] **Step 4: Build the example app for real**

Run: `cd packages/flutter_otel_native/example && flutter pub get`
Expected: resolves without error.

Run: `flutter build macos --debug`
Expected: succeeds — this compiles `NativeTelemetryCore` and `FlutterOtelNativePlugin` for real via CocoaPods and links them into a runnable macOS app.

Run: `flutter build ios --debug --simulator --no-codesign`
Expected: succeeds — same check for the iOS side, using a simulator build so no signing identity is required.

If either fails, the error will point at whichever Task 6–9 file has a mismatch (typically a podspec `source_files` glob path or a `Package.swift` relative path) — fix it there rather than in the example.

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_otel_native/example
git commit -m "feat(otel-native): add an example app that smoke-tests the native bridge end to end"
```

---

## Task 11: Workspace + CI

**Files:**

- Modify: `.github/workflows/ci.yml`

(The root `pubspec.yaml` workspace registration already happened in Task 3, Step 1.)

- [ ] **Step 1: Add `flutter_otel_native` to the existing Linux job**

In `.github/workflows/ci.yml`, insert this block after the `flutter_otel_sdk` steps and before the `flutter_otel` (umbrella) steps:

```yaml
# --- flutter_otel_native: depends on Flutter (MethodChannel). Only
# the Dart side is tested here — the Swift side has no Flutter
# dependency and is tested by the macos-native-tests job below,
# which needs no Xcode/iOS toolchain setup at all as a result.
- name: Analyze flutter_otel_native
  working-directory: packages/flutter_otel_native
  run: flutter analyze
- name: Test flutter_otel_native
  working-directory: packages/flutter_otel_native
  run: flutter test
```

- [ ] **Step 2: Add a macOS job for the Swift package's tests**

At the end of `.github/workflows/ci.yml` (same indentation level as the existing `ci:` job, under `jobs:`), add:

```yaml
macos-native-tests:
  # NativeTelemetryCore has no Flutter dependency, so this only needs
  # the Swift toolchain macos-latest ships with — no Flutter/Xcode
  # project setup required.
  runs-on: macos-latest
  steps:
    - uses: actions/checkout@v4
      with:
        persist-credentials: false

    - name: swift test (NativeTelemetryCore)
      working-directory: packages/flutter_otel_native/native/NativeTelemetryCore
      run: swift test
```

- [ ] **Step 3: Verify the added Dart steps locally before pushing**

Run: `cd packages/flutter_otel_native && flutter analyze && flutter test`
Expected: PASS (this should already be true from Tasks 3–5; this step exists to catch any drift before the CI file references it).

Run: `cd packages/flutter_otel_native/native/NativeTelemetryCore && swift test`
Expected: PASS (already true from Tasks 6–8).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "chore(ci): test flutter_otel_native's Dart and Swift sides"
```

---

## Task 12: Documentation

**Files:**

- Create: `packages/flutter_otel_native/README.md`
- Modify: `README.md` (root)

- [ ] **Step 1: Write the package README**

`packages/flutter_otel_native/README.md`:

```markdown
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

````

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
````

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

```

- [ ] **Step 2: Update the root README**

In `README.md`, add `flutter_otel_native` to the workspace layout tree (after the `flutter_otel_instrumentation_dio` entry):

```

    flutter_otel_instrumentation_dio/   # Dio HTTP client instrumentation,
                                         # including CLIENT spans + traceparent
                                         # propagation when a Tracer is given
    flutter_otel_native/                # native (Swift) telemetry foundation
                                         # for iOS/macOS: an on-disk queue +
                                         # MethodChannel bridge so native code
                                         # can record spans/logs before or
                                         # without a running Dart isolate

```

And to the package list just below it:

```

- [`packages/flutter_otel_instrumentation_dio`](packages/flutter_otel_instrumentation_dio/README.md)
- [`packages/flutter_otel_native`](packages/flutter_otel_native/README.md)

````

Add a short pointer under the existing "### Not yet implemented" section, after the `tracestate` propagation bullet:

```markdown
- **Native (Swift) instrumentation beyond the foundation** —
  `flutter_otel_native` provides the recording/queuing/bridging plumbing
  only; cold-start timing, native crash capture, background-task tracing,
  and native networking instrumentation are each a separate, later spec
  built on top of it (see `docs/superpowers/specs/` for the design).
````

- [ ] **Step 3: Commit**

```bash
git add packages/flutter_otel_native/README.md README.md
git commit -m "docs: document flutter_otel_native and its place in the roadmap"
```

---

## Self-review notes

- **Spec coverage:** every section of the design spec maps to a task —
  package/scaffold (Task 3), wire format (Tasks 3/8, kept identical),
  native components `NativeTelemetryRecorder`/`RecordQueue` (Tasks 7–8,
  `NativeTraceContext`'s responsibilities folded into
  `NativeTelemetryRecorder` itself rather than a separate class — a
  same-behavior simplification noted in Global Constraints), the
  platform-channel bridge (Tasks 5, 9), the core ingestion change (Tasks
  1–2), trace/session correlation (Tasks 5, 8), reliability (Task 7's cap
  - drop reporting), and testing (Swift XCTest in Tasks 6–8, Dart tests in
    Tasks 1–5). The spec's optional `recordTestEvent` debug method was
    dropped per its own "may drop if unneeded" allowance, since this plan
    has no on-device integration test to use it — flagged here, not silently
    omitted.
- **Type consistency check:** `NativeDrainResult`'s three fields, the
  `drainQueue` channel response shape (`records`/`droppedSinceLastDrain`),
  and the wire format's field names are used identically across Tasks
  3–5 and 7–9 (cross-checked against the Global Constraints block, which
  is the single source of truth every task was written against).
