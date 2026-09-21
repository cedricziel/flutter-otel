# flutter-otel

An [OpenTelemetry](https://opentelemetry.io/) client SDK for Flutter apps.

It implements the **logs** and **traces** signals today — structured log
records, spans with attributes/events/status, optional rolling session
tracking, JSON-encoded OTLP/HTTP exporters for both signals, and automatic
trace-to-log correlation (a log emitted while a span is active is
automatically stamped with that span's trace/span IDs, with no manual
plumbing) — with the core deliberately kept signal-agnostic (Resource + a
processor/exporter pipeline pattern shared across signals) so **metrics**
can slot in later without reshaping this code. W3C Trace Context
(`traceparent`) propagation is supported for outgoing HTTP requests via
`flutter_otel_instrumentation_dio`.

## Platform support

**iOS and macOS are the currently supported and tested platforms** (this
matches the first consuming app). The Dart-only packages
(`flutter_otel_api`, `flutter_otel_sdk`, `flutter_otel_exporter_otlp_http`,
`flutter_otel`, `flutter_otel_instrumentation_dio`,
`flutter_otel_instrumentation_messaging`) have nothing
iOS/macOS-specific in them — there are no platform channels and no native
code, only `http`, `uuid`, and Flutter's cross-platform
`WidgetsBindingObserver` — so Android, web, Windows, and Linux should work
but are not yet verified. `flutter_otel_native` is the one exception: it's
iOS/macOS-only by design, backed by native Swift and a `MethodChannel`
bridge (see below).

## Workspace layout

This repo is a [Dart workspace](https://dart.dev/tools/pub/workspaces)
(`pubspec.yaml` at the root declares the `workspace:` member list; the root
itself has no `lib/` and is not published). Each package under `packages/`
resolves against the others automatically via normal version constraints —
no `path:` dependencies, no melos, just `dart pub get` / `flutter pub get`
run once at the repo root.

```
flutter-otel/
  pubspec.yaml                          # workspace root manifest only
  packages/
    flutter_otel_api/                   # pure Dart core: Resource, log types,
                                         # Span/Tracer/TracerProvider,
                                         # processor/exporter interfaces,
                                         # W3C trace-context helpers, a
                                         # metrics stub
    flutter_otel_sdk/                   # concrete SDK: log/span processors,
                                         # session tracking, the OTelSdk facade
                                         # (depends on flutter_otel_api + Flutter)
    flutter_otel_exporter_otlp_http/    # OTLP/HTTP JSON log + span exporters
                                         # (pure Dart, depends on flutter_otel_api + http)
    flutter_otel/                       # umbrella package — what apps depend on
    flutter_otel_instrumentation_dio/   # Dio HTTP client instrumentation,
                                         # including CLIENT spans + traceparent
                                         # propagation when a Tracer is given
    flutter_otel_instrumentation_http/  # package:http client instrumentation:
                                         # CLIENT spans, traceparent, and
                                         # semconv header capture (redacted)
    flutter_otel_instrumentation_messaging/  # messaging-style tracing of
                                         # long-lived connections (WebSocket,
                                         # JSON-RPC): a connection span plus
                                         # linked send/receive message spans
    flutter_otel_native/                # native (Swift) telemetry foundation
                                         # for iOS/macOS: an on-disk queue +
                                         # MethodChannel bridge so native code
                                         # can record spans/logs before or
                                         # without a running Dart isolate
    flutter_otel_device_info/           # coarse, non-identifying device
                                         # attributes (OS, model, form factor)
                                         # for OTelResource, from an allowlist
```

Four packages (`flutter_otel_api`, `flutter_otel_exporter_otlp_http`,
`flutter_otel_instrumentation_dio`, and
`flutter_otel_instrumentation_messaging`) are pure Dart with no Flutter dependency,
so they also run on any Dart target (server, CLI, web) — that's the
"multiplatform" half of the design. `flutter_otel_sdk` and the `flutter_otel`
umbrella depend on Flutter for `WidgetsBindingObserver`-based session
lifecycle handling.

See each package's own README for its role, dependencies, and a usage
example specific to it:

- [`packages/flutter_otel_api`](packages/flutter_otel_api/README.md)
- [`packages/flutter_otel_sdk`](packages/flutter_otel_sdk/README.md)
- [`packages/flutter_otel_exporter_otlp_http`](packages/flutter_otel_exporter_otlp_http/README.md)
- [`packages/flutter_otel`](packages/flutter_otel/README.md)
- [`packages/flutter_otel_instrumentation_dio`](packages/flutter_otel_instrumentation_dio/README.md)
- [`packages/flutter_otel_instrumentation_http`](packages/flutter_otel_instrumentation_http/README.md)
- [`packages/flutter_otel_instrumentation_messaging`](packages/flutter_otel_instrumentation_messaging/README.md)
- [`packages/flutter_otel_native`](packages/flutter_otel_native/README.md)
- [`packages/flutter_otel_device_info`](packages/flutter_otel_device_info/README.md)

## Quick start

Apps depend on the umbrella package, `flutter_otel`, which re-exports the
full public API from the other four packages:

```yaml
dependencies:
  flutter_otel:
    git:
      url: https://github.com/cedricziel/flutter-otel
      ref: main # pin to a commit or tag in real usage
      path: packages/flutter_otel

# flutter_otel's own dependencies on its sibling packages are unpublished,
# so pub can't resolve them on its own — pin them here too, at the same
# ref, or pub get will fail.
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

```dart
import 'package:flutter_otel/flutter_otel.dart';

Future<void> main() async {
  final otel = await OTelSdk.initialize(
    OTelSdkConfig(
      resource: OTelResource(
        serviceName: 'my-app',
        serviceVersion: '1.0.0',
        deploymentEnvironment: 'production',
      ),
      otlpEndpoint: Uri.parse('https://collector.example.com'),
      otlpHeaders: {'Authorization': 'Bearer <token>'},
    ),
  );

  otel.getLogger().info('app started', attributes: {'cold_start': true});

  // A log emitted while this span is active is automatically stamped with
  // its traceId/spanId — no manual correlation needed.
  await otel.getTracer().startActiveSpan('load-config', (span) async {
    otel.getLogger().info('config loaded');
  });

  runApp(const MyApp());
}
```

`enabled: false` swaps in no-op exporters for both signals, so logging and
tracing calls are always safe to leave in place across debug/release builds
without producing network traffic.

### Configuration naming

`OTelSdkConfig`'s `otlpEndpoint` / `otlpLogsEndpoint` / `otlpTracesEndpoint`
/ `otlpHeaders` fields mirror the standard OpenTelemetry environment
variable names (`OTEL_EXPORTER_OTLP_ENDPOINT`,
`OTEL_EXPORTER_OTLP_LOGS_ENDPOINT`, `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`,
`OTEL_EXPORTER_OTLP_HEADERS`) in behavior: `otlpEndpoint` is a general base
endpoint that the logs exporter resolves `/v1/logs` against and the traces
exporter resolves `/v1/traces` against, while `otlpLogsEndpoint` /
`otlpTracesEndpoint` — when set — are used verbatim as signal-specific
overrides, exactly like the env vars' base-vs-per-signal precedence. Batch
tuning (`maxQueueSize`, `maxExportBatchSize`, `scheduledDelay`) and
`httpClient` are shared across both signals rather than duplicated
per-signal — a deliberate simplification for now.

### Traces and correlation

`Tracer.startActiveSpan` starts a span, makes it the ambient
"current span" for the duration of the callback (propagated across `await`
gaps, including through nested spans), ends it when the callback returns
(recording the exception and setting an error status if it throws), and
returns the callback's result:

```dart
final result = await otel.getTracer().startActiveSpan('fetch-widgets', (span) async {
  span.setAttribute('widget.count', widgets.length);
  return widgets;
});
```

Any `Logger.emit`/`info`/`warn`/... call made anywhere underneath that
callback — directly or several layers of `await` down — automatically picks
up the active span's `traceId`/`spanId`, unless the caller already set them
explicitly. This is what makes trace-to-log correlation "automatic": no log
call site needs to know about tracing at all.

For outgoing HTTP requests, `flutter_otel_instrumentation_dio`'s
`DioOTelInterceptor` accepts an optional `tracer:` parameter that starts a
CLIENT span per request and injects a W3C `traceparent` header, joining the
request into whatever trace is active when it's made — see that package's
README for details.

### Not yet implemented

- **Sampling** — every span is always recorded and exported; there is no
  head- or tail-based sampling yet.
- **An `onStart` `SpanProcessor` hook** — only `onEnd` exists, since nothing
  in this SDK needs to observe a span before it finishes.
- **Metrics** — the core has a `Meter`/`MeterProvider` stub (see
  `flutter_otel_api`), but no metrics pipeline exists yet.
- **`tracestate` propagation** — `formatTraceparent`/`parseTraceparent`
  handle the W3C `traceparent` header only; this SDK has no vendor-specific
  state to carry in `tracestate` and doesn't round-trip anyone else's.
- **Native (Swift) instrumentation beyond the foundation** —
  `flutter_otel_native` provides the recording/queuing/bridging plumbing
  only; cold-start timing, native crash capture, background-task tracing,
  and native networking instrumentation are each a separate, later spec
  built on top of it (see `docs/superpowers/specs/` for the design).

## Development

```bash
flutter pub get              # resolves the whole workspace, run at the root
dart format .                # format check across every package
cd packages/<name> && flutter analyze && flutter test   # Flutter packages
cd packages/<name> && dart analyze && dart test          # pure-Dart packages
```

CI (`.github/workflows/ci.yml`) runs all of the above on every push and pull
request.
