// Deliberately does NOT call `TestWidgetsFlutterBinding.ensureInitialized()`
// (unlike the other test files in this package) so this file exercises the
// scenario of a consumer calling `OTelSdk.initialize(...)` as the very first
// line of `main()`, before any Flutter binding has been set up.
import 'package:flutter_otel/flutter_otel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_log_record_exporter.dart';

void main() {
  tearDown(() async {
    await OTelSdk.reset();
  });

  test(
      'initialize does not throw when called with no prior Flutter binding '
      'setup and session tracking enabled (the default)', () async {
    await expectLater(
      OTelSdk.initialize(
        OTelSdkConfig(
          resource: OTelResource(serviceName: 'test'),
          logExporter: FakeLogRecordExporter(),
        ),
      ),
      completes,
    );
  });
}
