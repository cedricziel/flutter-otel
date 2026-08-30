# flutter-otel

An [OpenTelemetry](https://opentelemetry.io/) client SDK for Flutter apps.

It implements the **logs** signal today — structured log records, optional
rolling session tracking, and a JSON-encoded OTLP/HTTP exporter — with the
core deliberately kept signal-agnostic (Resource + a processor/exporter
pipeline pattern shared across signals) so **traces** and **metrics** can
slot in later without reshaping the logs code.

## Platform support

**iOS and macOS are the currently supported and tested platforms** (this
matches the first consuming app). Nothing in the implementation is
iOS/macOS-specific, though — there are no platform channels and no native
code, only `http`, `uuid`, and Flutter's cross-platform
`WidgetsBindingObserver` — so Android, web, Windows, and Linux should work
but are not yet verified.

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
                                         # processor/exporter interfaces,
                                         # trace/metric stubs
    flutter_otel_sdk/                   # concrete SDK: processors, session
                                         # tracking, the OTelSdk facade
                                         # (depends on flutter_otel_api + Flutter)
    flutter_otel_exporter_otlp_http/    # OTLP/HTTP JSON log exporter
                                         # (pure Dart, depends on flutter_otel_api + http)
    flutter_otel/                       # umbrella package — what apps depend on
    flutter_otel_instrumentation_dio/   # Dio HTTP client instrumentation
```

Three packages (`flutter_otel_api`, `flutter_otel_exporter_otlp_http`, and
`flutter_otel_instrumentation_dio`) are pure Dart with no Flutter dependency,
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

  runApp(const MyApp());
}
```

`enabled: false` swaps in a no-op exporter, so logging calls are always safe
to leave in place across debug/release builds without producing network
traffic.

### Configuration naming

`OTelSdkConfig`'s `otlpEndpoint` / `otlpLogsEndpoint` / `otlpHeaders` fields
mirror the standard OpenTelemetry environment variable names
(`OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT`,
`OTEL_EXPORTER_OTLP_HEADERS`) in behavior: `otlpEndpoint` is a general base
endpoint that the logs exporter resolves `/v1/logs` against, while
`otlpLogsEndpoint` — when set — is used verbatim as a signal-specific
override, exactly like the env vars' base-vs-per-signal precedence.

## Development

```bash
flutter pub get              # resolves the whole workspace, run at the root
dart format .                # format check across every package
cd packages/<name> && flutter analyze && flutter test   # Flutter packages
cd packages/<name> && dart analyze && dart test          # pure-Dart packages
```

CI (`.github/workflows/ci.yml`) runs all of the above on every push and pull
request.
