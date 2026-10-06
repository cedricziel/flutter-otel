# flutter_otel_device_info

Coarse, non-identifying device attributes for OpenTelemetry resources in
Flutter apps, and an opt-in, vendor-scoped installation ID. Both return a plain
`Map<String, Object>`, so the package has no dependency on the other
`flutter_otel` packages.

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

## Installation ID (opt-in)

`detectAppInstallationId` returns `app.installation.id`, an identifier for
this installation of the app scoped to its vendor. It identifies one device,
so call it only where your users have agreed to that:

```dart
final resource = OTelResource(
  serviceName: 'my-app',
  attributes: {
    ...await detectDeviceAttributes(),
    ...await detectAppInstallationId(),
  },
);
```

| Platform                | Source                                                                 |
| ----------------------- | ---------------------------------------------------------------------- |
| iOS                     | `identifierForVendor`, reset once all of the vendor's apps are removed |
| Android                 | `ANDROID_ID`, scoped to the app's signing key, user and device (Android 8+) |
| macOS, Windows, Linux   | a random UUID kept in the app's support directory                      |

It follows the OpenTelemetry semantic conventions, which recommend the vendor
identifier on iOS for `app.installation.id`. It does not set `device.id`,
which the conventions reserve for an ID shared by every app on the device and
advise against in consumer apps. No hardware ID is read. Like
`detectDeviceAttributes`, it never throws: when the identifier cannot be read
or stored, the map is empty. On App Store and Google Play, declare it as a
device ID in the app's privacy details.

## Privacy

`detectDeviceAttributes` returns only the attributes listed under Attributes, an explicit
allowlist, and nothing else is read from the device. In particular it never
reads or returns:

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
`DeviceInfoPlugin` to substitute. `detectAppInstallationId` accepts the same
kind of substitutes, including the directory the desktop ID is kept in.

## Dependencies

`device_info_plus` is accepted from 12.4.0 up to, but excluding, 14.0.0, so an
app held on 12.x by another dependency and an app on 13.x both resolve.
