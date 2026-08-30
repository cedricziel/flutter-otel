// Smoke test proving the umbrella package's single import surfaces the full
// public API contract from flutter_otel_api, flutter_otel_sdk, and
// flutter_otel_exporter_otlp_http without needing separate imports.
import 'package:flutter_otel/flutter_otel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await OTelSdk.reset();
  });

  test('the full public API is reachable from a single umbrella import',
      () async {
    final resource =
        OTelResource(serviceName: 'trueapp', serviceVersion: '1.0.0');
    final exporter = OtlpHttpLogExporter(
      endpoint: Uri.parse('https://collector.example.com/v1/logs'),
      httpClient: MockClient((request) async => http.Response('ok', 200)),
    );

    final sdk = await OTelSdk.initialize(
      OTelSdkConfig(resource: resource, logExporter: exporter),
    );

    final logger = sdk.getLogger();
    logger.info('hello from the umbrella package', attributes: {'k': 'v'});
    await sdk.forceFlush();

    expect(sdk.loggerProvider, isNotNull);
    expect(sdk.sessionManager, isNotNull);
    expect(LogSeverity.info.severityNumber, 9);
    expect(const NoopLogRecordExporter(), isA<LogRecordExporter>());
    expect(const NoopTracerProvider().getTracer(), isA<Tracer>());
    expect(const NoopMeterProvider().getMeter(), isA<Meter>());

    await sdk.shutdown();
  });
}
