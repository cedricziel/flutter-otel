// Smoke test proving the umbrella package's single import surfaces the full
// public API contract from flutter_otel_api, flutter_otel_sdk, and
// flutter_otel_exporter_otlp_http without needing separate imports.
import 'dart:convert';

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
    String? capturedLogBody;
    final logExporter = OtlpHttpLogExporter(
      endpoint: Uri.parse('https://collector.example.com/v1/logs'),
      httpClient: MockClient((request) async {
        capturedLogBody = request.body;
        return http.Response('ok', 200);
      }),
    );
    final spanExporter = OtlpHttpSpanExporter(
      endpoint: Uri.parse('https://collector.example.com/v1/traces'),
      httpClient: MockClient((request) async => http.Response('ok', 200)),
    );

    final sdk = await OTelSdk.initialize(
      OTelSdkConfig(
        resource: resource,
        logExporter: logExporter,
        spanExporter: spanExporter,
      ),
    );

    final logger = sdk.getLogger();
    logger.info('hello from the umbrella package', attributes: {'k': 'v'});
    await sdk.forceFlush();

    expect(sdk.loggerProvider, isNotNull);
    expect(sdk.tracerProvider, isNotNull);
    expect(sdk.sessionManager, isNotNull);
    expect(LogSeverity.info.severityNumber, 9);
    expect(const NoopLogRecordExporter(), isA<LogRecordExporter>());
    expect(const NoopTracerProvider().getTracer(), isA<Tracer>());
    expect(const NoopSpanExporter(), isA<SpanExporter>());
    expect(const NoopMeterProvider().getMeter(), isA<Meter>());

    // Traces + automatic trace-to-log correlation, all reachable from the
    // umbrella import alone.
    SpanContext? activeContext;
    await sdk.getTracer().startActiveSpan('op', (span) async {
      activeContext = span.spanContext;
      span.setAttribute('k', 'v');
      span.addEvent('checkpoint');
      span.setStatus(StatusCode.ok);
      logger.info('inside a span');
    });
    await sdk.forceFlush();

    expect(activeContext, isNotNull);
    expect(activeContext!.isValid, isTrue);
    expect(formatTraceparent(activeContext!), startsWith('00-'));
    expect(parseTraceparent(formatTraceparent(activeContext!)), isNotNull);

    // The exported log record actually carries the active span's
    // trace/span IDs, end to end through the real OTLP/HTTP exporter.
    final decoded = jsonDecode(capturedLogBody!) as Map<String, dynamic>;
    final logRecord = ((decoded['resourceLogs'] as List).single
            as Map<String, dynamic>)['scopeLogs']
        .first['logRecords']
        .first as Map<String, dynamic>;
    expect(logRecord['traceId'], activeContext!.traceId);
    expect(logRecord['spanId'], activeContext!.spanId);

    await sdk.shutdown();
  });
}
