import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Detects an identifier for this app's installation, scoped to its vendor,
/// as the `app.installation.id` resource attribute.
///
/// Unlike `detectDeviceAttributes`, this identifies one device, so call it
/// only where users have agreed to that.
///
/// - iOS: the vendor identifier (`identifierForVendor`), shared by the
///   vendor's apps on the device and reset once all of them are removed.
/// - Android: `ANDROID_ID`, which since Android 8 is scoped to the app's
///   signing key, the user and the device.
/// - Elsewhere: a random UUID created on first use and kept in the app's
///   support directory, since these systems have no vendor identifier.
///
/// No hardware ID is ever read. This function never throws: if the identifier
/// cannot be read or stored, for example on iOS before the first unlock after
/// a restart, the result is empty. [plugin], [androidId] and [directory]
/// substitute the platform sources in tests.
Future<Map<String, Object>> detectAppInstallationId({
  DeviceInfoPlugin? plugin,
  AndroidId? androidId,
  Future<Directory> Function()? directory,
}) async {
  try {
    final id = switch (Platform.operatingSystem) {
      'ios' =>
        (await (plugin ?? DeviceInfoPlugin()).iosInfo).identifierForVendor,
      'android' => await (androidId ?? const AndroidId()).getId(),
      _ => await _readOrCreate(
        await (directory ?? getApplicationSupportDirectory)(),
      ),
    };
    return {if (id != null && id.isNotEmpty) 'app.installation.id': id};
  } catch (_) {
    return const {};
  }
}

Future<String> _readOrCreate(Directory directory) async {
  final file = File('${directory.path}/opentelemetry_app_installation_id');
  if (await file.exists()) {
    final stored = (await file.readAsString()).trim();
    if (Uuid.isValidUUID(fromString: stored)) return stored;
  }
  final id = const Uuid().v4();
  await directory.create(recursive: true);
  await file.writeAsString(id, flush: true);
  return id;
}
