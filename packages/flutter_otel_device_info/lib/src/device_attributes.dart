import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Detects coarse, non-identifying attributes of the device the app runs on,
/// ready to pass as `OTelResource(attributes: ...)`.
///
/// Every value comes from an explicit allowlist: the operating system and its
/// version, the hardware model (an identifier shared by every unit of it, such
/// as `iPhone17,1`), phone, tablet or desktop, the CPU architecture, whether
/// the device is a simulator, and the build mode. Attributes that do not apply
/// to the platform, or that cannot be read, are left out.
///
/// It never reads or returns the device name, vendor or hardware IDs, GUIDs,
/// locale, memory or disk sizes, or build fingerprints.
///
/// This function never throws. If the device plugin is unavailable or refuses,
/// the attributes that need no plugin are returned; if even those cannot be
/// determined, the result is empty. Pass [plugin] to substitute the
/// [DeviceInfoPlugin], for example in tests.
Future<Map<String, Object>> detectDeviceAttributes({
  DeviceInfoPlugin? plugin,
}) async {
  final String os;
  final Map<String, Object> basics;
  try {
    os = Platform.operatingSystem;
    basics = describeDevice(
      os: os,
      osVersion: Platform.operatingSystemVersion,
      shortestSideLogical: _shortestSideLogical(),
      buildMode: kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
    );
  } catch (_) {
    return const {};
  }
  try {
    return {...basics, ...await _hardware(os, plugin ?? DeviceInfoPlugin())};
  } catch (_) {
    return basics;
  }
}

Future<Map<String, Object>> _hardware(
  String os,
  DeviceInfoPlugin plugin,
) async {
  switch (os) {
    case 'ios':
      final info = await plugin.iosInfo;
      return describeApple(
        family: info.model,
        identifier: info.utsname.machine,
        simulator: !info.isPhysicalDevice,
        iosAppOnMac: info.isiOSAppOnMac,
      );
    case 'macos':
      final info = await plugin.macOsInfo;
      return describeApple(identifier: info.model, arch: info.arch);
    case 'android':
      final info = await plugin.androidInfo;
      return describeAndroid(
        manufacturer: info.manufacturer,
        model: info.model,
        release: info.version.release,
        apiLevel: info.version.sdkInt,
        simulator: !info.isPhysicalDevice,
      );
    default:
      return const {};
  }
}

/// The platform-independent attributes behind [detectDeviceAttributes], as a
/// pure function of what the platform reports.
///
/// [os] is `Platform.operatingSystem`. [osVersion] is
/// `Platform.operatingSystemVersion`; only iOS and macOS versions are kept
/// (reduced to major.minor, without the build number), since other systems
/// report a kernel string that is neither short nor useful.
/// [shortestSideLogical] is the shortest screen side in logical pixels: on iOS
/// and Android a side of 600 or more is a tablet, and the form factor is left
/// out while the side is unknown or not positive. macOS, Windows and Linux
/// are always `desktop`. [buildMode] is `release`, `profile` or `debug`.
Map<String, Object> describeDevice({
  required String os,
  required String osVersion,
  required double? shortestSideLogical,
  required String buildMode,
}) {
  final version = _majorMinor(os, osVersion);
  final formFactor = _formFactor(os, shortestSideLogical);
  return {
    'os.type': os,
    'os.version': ?version,
    'device.form_factor': ?formFactor,
    'app.build_mode': buildMode,
  };
}

/// The hardware attributes of an iPhone, iPad or Mac.
///
/// [family] is the marketing family (`iPhone`, `iPad`), which says phone or
/// tablet more reliably than the screen does; without it, or for anything
/// else, the form factor is left out. [identifier] is the model identifier,
/// such as `iPhone17,1` or `Mac14,2`. [arch], [simulator] and [iosAppOnMac]
/// are included only when given.
Map<String, Object> describeApple({
  String? family,
  required String identifier,
  String? arch,
  bool? simulator,
  bool? iosAppOnMac,
}) {
  final formFactor = switch (family?.toLowerCase()) {
    final f? when f.startsWith('ipad') => 'tablet',
    final f? when f.startsWith('iphone') || f.startsWith('ipod') => 'phone',
    _ => null,
  };
  return {
    'device.manufacturer': 'Apple',
    'device.model.identifier': identifier,
    'device.form_factor': ?formFactor,
    'host.arch': ?arch,
    'device.simulator': ?simulator,
    'app.ios_app_on_mac': ?iosAppOnMac,
  };
}

/// The hardware attributes of an Android device.
///
/// [manufacturer] and [model] are the values Android reports, [release] is the
/// user-visible version (`15`), [apiLevel] the SDK level (`35`), and
/// [simulator] is true for an emulator.
Map<String, Object> describeAndroid({
  required String manufacturer,
  required String model,
  required String release,
  required int apiLevel,
  required bool simulator,
}) => {
  'device.manufacturer': manufacturer,
  'device.model.identifier': model,
  'os.version': release,
  'android.os.api_level': apiLevel,
  'device.simulator': simulator,
};

String? _majorMinor(String os, String osVersion) {
  if (os != 'ios' && os != 'macos') return null;
  return RegExp(r'(\d+(?:\.\d+)?)').firstMatch(osVersion)?.group(1);
}

String? _formFactor(String os, double? shortestSide) {
  switch (os) {
    case 'macos' || 'windows' || 'linux':
      return 'desktop';
    case 'ios' || 'android':
      if (shortestSide == null || shortestSide <= 0) return null;
      return shortestSide >= 600 ? 'tablet' : 'phone';
    default:
      return null;
  }
}

double? _shortestSideLogical() {
  final view = PlatformDispatcher.instance.implicitView;
  if (view == null) return null;
  final size = view.physicalSize / view.devicePixelRatio;
  return size.shortestSide;
}
