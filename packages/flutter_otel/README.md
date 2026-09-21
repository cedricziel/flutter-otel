# flutter_otel

The umbrella "batteries included" package — **this is what apps depend
on**. It re-exports the full public API from
[`dart_otel_api`](../dart_otel_api/README.md),
[`dart_otel_sdk`](../dart_otel_sdk/README.md), and
[`dart_otel_exporter_otlp_http`](../dart_otel_exporter_otlp_http/README.md)
so a single import gives you everything.

**Platform support:** iOS and macOS are the currently supported and tested
targets. Android, web, Windows, and Linux should work (nothing here is
platform-specific — no platform channels, just `http`, `uuid`, and
`WidgetsBindingObserver`) but are not yet verified.

## Position in the dependency graph

```text
dart_otel_api ──┬──────────────────────────────┐
                    │                              │
dart_otel_exporter_otlp_http ──> dart_otel_sdk ──> flutter_otel
```

`flutter_otel` depends on all three of the packages above and exports them
verbatim through `lib/flutter_otel.dart`. Nothing in the workspace depends
on `flutter_otel` itself — it's the leaf apps consume.

## Install

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
  dart_otel_api:
    git:
      url: https://github.com/cedricziel/flutter-otel
      ref: main
      path: packages/dart_otel_api
  dart_otel_sdk:
    git:
      url: https://github.com/cedricziel/flutter-otel
      ref: main
      path: packages/dart_otel_sdk
  dart_otel_exporter_otlp_http:
    git:
      url: https://github.com/cedricziel/flutter-otel
      ref: main
      path: packages/dart_otel_exporter_otlp_http
```

## Usage example

```dart
import 'package:flutter_otel/flutter_otel.dart';

Future<void> main() async {
  final otel = await OTelSdk.initialize(
    OTelSdkConfig(
      resource: OTelResource(serviceName: 'my-app', serviceVersion: '1.0.0'),
      otlpEndpoint: Uri.parse('https://collector.example.com'),
    ),
  );

  otel.getLogger().info('app started');

  // A log emitted while this span is active is automatically stamped with
  // its traceId/spanId — no manual correlation needed.
  await otel.getTracer().startActiveSpan('load-config', (span) async {
    otel.getLogger().info('config loaded');
  });

  runApp(const MyApp());
}
```

See the [root README](../../README.md) for the full quick-start, the
traces/correlation walkthrough, and the `OTEL_EXPORTER_OTLP_*`
configuration naming convention this SDK mirrors.

## App events and uncaught errors

`appEventLogger` records that something happened, as an info log record with a
fixed name and a few plain attributes. Pass only fixed names and coarse values
(a state, a status code, a reason slug), never URLs, hosts or exception
messages. `noopAppEventLogger` has the same signature for when telemetry is
off. Neither ever throws.

```dart
final AppEventLogger logEvent = appEventLogger(otel.getLogger());

logEvent('auth.state', {'state': 'ready'});
```

`installUncaughtErrorLogging` hooks `FlutterError.onError` and
`PlatformDispatcher.instance.onError` and emits an error record per uncaught
error. Only the exception type is recorded (`exception.type`), because
messages and stack traces can carry user input. The previously installed
handlers still run and their result is preserved.

```dart
installUncaughtErrorLogging(otel.getLogger());
```

## Testing

```bash
cd packages/flutter_otel
flutter pub get   # or rely on the workspace root's `flutter pub get`
flutter analyze
flutter test
```
