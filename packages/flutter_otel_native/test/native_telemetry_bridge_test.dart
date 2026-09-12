import 'package:flutter/services.dart';
import 'package:flutter_otel_native/flutter_otel_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_logger_provider.dart';
import 'support/fake_tracer_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_otel_native');
  late FakeTracerProvider tracerProvider;
  late FakeLoggerProvider loggerProvider;
  late NativeTelemetryBridge bridge;

  setUp(() {
    tracerProvider = FakeTracerProvider();
    loggerProvider = FakeLoggerProvider();
    bridge = NativeTelemetryBridge(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mockDrainResponse(Map<String, Object?> response) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'drainQueue');
      return response;
    });
  }

  test('ingests a mix of decodable span and log lines', () async {
    mockDrainResponse({
      'records': [
        '{"kind":"span","name":"op","traceId":'
            '"4bf92f3577b34da6a3ce929d0e0e4736","spanId":'
            '"00f067aa0ba902b7","parentSpanId":null,"spanKind":"internal",'
            '"startTimeUnixNano":"1700000000000000000","endTimeUnixNano":'
            '"1700000000050000000","attributes":{},"events":[],'
            '"statusCode":"unset","scopeName":"flutter_otel_native"}',
        '{"kind":"log","timeUnixNano":"1700000000010000000","severity":'
            '"info","body":"hi","attributes":{}}',
      ],
      'droppedSinceLastDrain': 0,
    });

    final result = await bridge.drainAndForward(
      tracerProvider: tracerProvider,
      loggerProvider: loggerProvider,
    );

    expect(result.recordsIngested, 2);
    expect(result.recordsSkipped, 0);
    expect(result.recordsDropped, 0);
    expect(tracerProvider.ingestedSpans, hasLength(1));
    expect(loggerProvider.ingestedRecords, hasLength(1));
  });

  test('counts malformed lines as skipped instead of throwing', () async {
    mockDrainResponse({
      'records': ['not json', '{"kind":"metric"}'],
      'droppedSinceLastDrain': 0,
    });

    final result = await bridge.drainAndForward(
      tracerProvider: tracerProvider,
      loggerProvider: loggerProvider,
    );

    expect(result.recordsIngested, 0);
    expect(result.recordsSkipped, 2);
  });

  test('surfaces the native drop count unchanged', () async {
    mockDrainResponse({'records': <String>[], 'droppedSinceLastDrain': 7});

    final result = await bridge.drainAndForward(
      tracerProvider: tracerProvider,
      loggerProvider: loggerProvider,
    );

    expect(result.recordsDropped, 7);
  });

  test('treats a null response as an empty drain', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final result = await bridge.drainAndForward(
      tracerProvider: tracerProvider,
      loggerProvider: loggerProvider,
    );

    expect(result.recordsIngested, 0);
    expect(result.recordsSkipped, 0);
    expect(result.recordsDropped, 0);
  });
}
