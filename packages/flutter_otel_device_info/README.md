# flutter_otel_device_info

Coarse, non-identifying device attributes for OpenTelemetry resources in
Flutter apps. It returns a plain `Map<String, Object>`, so it has no
dependency on the other `flutter_otel` packages.

**Platform support:** iOS, macOS and Android report hardware details; Windows
and Linux report the basics only (OS, form factor, build mode). On web the
platform cannot be read and the map is empty.

## Usage

```dart
import 'package:flutter_otel/flutter_otel.dart';
import 'package:flutter_otel_device_info/flutter_otel_device_info.dart';

final resource = OTelResource(
  serviceName: 'my-app',
  attributes: await detectDeviceAttributes(),
);
```

`detectDeviceAttributes` never throws. If the device plugin is unavailable or
refuses, it returns the attributes that need no plugin; if those cannot be
determined either, it returns an empty map.

## Attributes

| Attribute                 | Value                                            | Platforms       |
| ------------------------- | ------------------------------------------------ | --------------- |
| `os.type`                 | `ios`, `macos`, `android`, `windows`, `linux`    | all             |
| `os.version`              | major.minor on iOS and macOS, release on Android | iOS, macOS, Android |
| `device.form_factor`      | `phone`, `tablet` or `desktop`                   | all             |
| `app.build_mode`          | `release`, `profile` or `debug`                  | all             |
| `device.manufacturer`     | `Apple`, or the Android manufacturer             | iOS, macOS, Android |
| `device.model.identifier` | model identifier, such as `iPhone17,1`, `Mac14,2` or `Pixel 9` | iOS, macOS, Android |
| `host.arch`               | CPU architecture, such as `arm64`                | macOS           |
| `device.simulator`        | whether it is a simulator or emulator            | iOS, Android    |
| `app.ios_app_on_mac`      | whether an iOS app runs on a Mac                 | iOS             |
| `android.os.api_level`    | Android SDK level                                | Android         |

## Privacy

The attributes above are an explicit allowlist, and nothing else is read from
the device. In particular this package never reads or returns:

- the device name or host name
- vendor or hardware IDs, serial numbers or GUIDs
- the locale
- memory or disk sizes
- build fingerprints or full kernel and build strings

The hardware model identifier is shared by every unit of that model, so it
tells devices apart by type, not one device from another.

## Testing

The pure functions `describeDevice`, `describeApple` and `describeAndroid` are
exported and turn what a platform reports into attributes, so any platform can
be exercised without a device. `detectDeviceAttributes` accepts a
`DeviceInfoPlugin` to substitute.

## Dependencies

`device_info_plus` is accepted from 12.4.0 up to, but excluding, 14.0.0, so an
app held on 12.x by another dependency and an app on 13.x both resolve.
