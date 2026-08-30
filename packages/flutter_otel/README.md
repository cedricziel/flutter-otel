# flutter_otel

The umbrella "batteries included" package — **this is what apps depend
on**. It re-exports the full public API from
[`flutter_otel_api`](../flutter_otel_api/README.md),
[`flutter_otel_sdk`](../flutter_otel_sdk/README.md), and
[`flutter_otel_exporter_otlp_http`](../flutter_otel_exporter_otlp_http/README.md)
so a single import gives you everything.

**Platform support:** iOS and macOS are the currently supported and tested
targets. Android, web, Windows, and Linux should work (nothing here is
platform-specific — no platform channels, just `http`, `uuid`, and
`WidgetsBindingObserver`) but are not yet verified.

## Position in the dependency graph

```text
flutter_otel_api ──┬──────────────────────────────┐
                    │                              │
flutter_otel_exporter_otlp_http ──> flutter_otel_sdk ──> flutter_otel
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

## Testing

```bash
cd packages/flutter_otel
flutter pub get   # or rely on the workspace root's `flutter pub get`
flutter analyze
flutter test
```
