import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_otel_device_info/flutter_otel_device_info.dart';
import 'package:flutter_test/flutter_test.dart';

class _RefusingPlugin implements DeviceInfoPlugin {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('platform refused');
}

void main() {
  test('describes an iPhone by system, version and form factor only', () {
    expect(
      describeDevice(
        os: 'ios',
        osVersion: 'Version 26.0 (Build 23A344)',
        shortestSideLogical: 393,
        buildMode: 'release',
      ),
      {
        'os.type': 'ios',
        'os.version': '26.0',
        'device.form_factor': 'phone',
        'app.build_mode': 'release',
      },
    );
  });

  test('tells a tablet from a phone by its shortest side', () {
    Object? formFactor(double side) => describeDevice(
      os: 'ios',
      osVersion: 'Version 26.0',
      shortestSideLogical: side,
      buildMode: 'release',
    )['device.form_factor'];

    expect(formFactor(599), 'phone');
    expect(formFactor(834), 'tablet');
  });

  test('a Mac is a desktop and the build number stays out', () {
    final attributes = describeDevice(
      os: 'macos',
      osVersion: 'Version 15.6.1 (Build 24G90)',
      shortestSideLogical: 900,
      buildMode: 'release',
    );

    expect(attributes['device.form_factor'], 'desktop');
    expect(attributes['os.version'], '15.6');
  });

  test('leaves out what it cannot say briefly or does not know yet', () {
    final attributes = describeDevice(
      os: 'android',
      osVersion: 'Linux 6.1.75-android14-11 #1 SMP PREEMPT',
      shortestSideLogical: 0,
      buildMode: 'release',
    );

    expect(attributes, {'os.type': 'android', 'app.build_mode': 'release'});
  });

  group('describeApple', () {
    test('an iPhone is a phone with its model identifier', () {
      expect(
        describeApple(
          family: 'iPhone',
          identifier: 'iPhone17,1',
          simulator: false,
          iosAppOnMac: false,
        ),
        {
          'device.manufacturer': 'Apple',
          'device.model.identifier': 'iPhone17,1',
          'device.form_factor': 'phone',
          'device.simulator': false,
          'app.ios_app_on_mac': false,
        },
      );
    });

    test('an iPad is a tablet even on a small screen', () {
      final attributes = describeApple(
        family: 'iPad',
        identifier: 'iPad16,3',
        simulator: false,
        iosAppOnMac: false,
      );

      expect(attributes['device.form_factor'], 'tablet');
    });

    test('a Mac reports its architecture and no phone or tablet', () {
      final attributes = describeApple(identifier: 'Mac14,2', arch: 'arm64');

      expect(attributes['host.arch'], 'arm64');
      expect(attributes, isNot(contains('device.form_factor')));
    });
  });

  test('describeAndroid reports make, model and API level', () {
    expect(
      describeAndroid(
        manufacturer: 'Google',
        model: 'Pixel 9',
        release: '15',
        apiLevel: 35,
        simulator: false,
      ),
      {
        'device.manufacturer': 'Google',
        'device.model.identifier': 'Pixel 9',
        'os.version': '15',
        'android.os.api_level': 35,
        'device.simulator': false,
      },
    );
  });

  test('keeps the basics when the device plugin is unavailable', () async {
    final attributes = await detectDeviceAttributes();

    expect(attributes, contains('os.type'));
    expect(attributes, contains('app.build_mode'));
  });

  test('keeps the basics when the device plugin throws', () async {
    final attributes = await detectDeviceAttributes(plugin: _RefusingPlugin());

    expect(attributes, contains('os.type'));
    expect(attributes, contains('app.build_mode'));
  });
}
