# flutter_otel_sdk

The concrete OpenTelemetry SDK implementation for Flutter: log processors,
session tracking, and the `OTelSdk` facade. This is where the interfaces
declared in [`flutter_otel_api`](../flutter_otel_api/README.md) get real
implementations.

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

- `SimpleLogRecordProcessor` — exports each record immediately; good for
  dev/tests.
- `BatchLogRecordProcessor` — batches records (`maxQueueSize`,
  `maxExportBatchSize`, `scheduledDelay`), flushing on a periodic timer or
  once a batch fills up; swallows export failures via `debugPrint` instead
  of throwing into app code.
- `SdkLoggerProvider` — the concrete `LoggerProvider`; when session tracking
  is enabled, every `Logger` it vends merges a `session.id` attribute onto
  each emitted record and calls `SessionManager.touch()`.
- `DefaultSessionManager` — generates a new session ID once more than the
  configured idle timeout (default 30 minutes) has elapsed between
  `touch()` calls, and (optionally) registers a `WidgetsBindingObserver` so
  resuming from the background after a long gap starts a new session.
- `OTelSdkConfig` / `OTelSdk` — the configuration object and top-level
  facade apps actually call.

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
      // Bring your own exporter, e.g. flutter_otel_exporter_otlp_http's
      // OtlpHttpLogExporter, or a fake for tests.
      logExporter: const NoopLogRecordExporter(),
    ),
  );

  sdk.getLogger().info('hello from flutter_otel_sdk');
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
