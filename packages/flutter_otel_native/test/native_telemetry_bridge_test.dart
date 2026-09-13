import 'package:flutter/services.dart';
import 'package:flutter_otel_api/flutter_otel_api.dart';
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

  group('session and trace-context primitives', () {
    test('setSessionId invokes the channel with the session id', () async {
      MethodCall? invoked;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        invoked = call;
        return null;
      });

      await bridge.setSessionId('session-123');

      expect(invoked?.method, 'setSessionId');
      expect(invoked?.arguments, {'sessionId': 'session-123'});
    });

    test(
      'setCurrentTraceContext invokes the channel with traceId/spanId',
      () async {
        MethodCall? invoked;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          invoked = call;
          return null;
        });

        await bridge.setCurrentTraceContext(
          const SpanContext(
            traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
            spanId: '00f067aa0ba902b7',
          ),
        );

        expect(invoked?.method, 'setCurrentTraceContext');
        expect(invoked?.arguments, {
          'traceId': '4bf92f3577b34da6a3ce929d0e0e4736',
          'spanId': '00f067aa0ba902b7',
        });
      },
    );

    test(
      'clearCurrentTraceContext invokes the channel with no arguments',
      () async {
        MethodCall? invoked;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          invoked = call;
          return null;
        });

        await bridge.clearCurrentTraceContext();

        expect(invoked?.method, 'clearCurrentTraceContext');
      },
    );
  });

  group('distributionEnvironment', () {
    test('returns whatever native reports', () async {
      MethodCall? invoked;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        invoked = call;
        return 'testflight';
      });

      final result = await bridge.distributionEnvironment();

      expect(invoked?.method, 'distributionEnvironment');
      expect(result, 'testflight');
    });

    test('returns "development" when native returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);

      final result = await bridge.distributionEnvironment();

      expect(result, 'development');
    });

    test(
      'returns "development" rather than throwing when the channel fails',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(code: 'unavailable'),
        );

        final result = await bridge.distributionEnvironment();

        expect(result, 'development');
      },
    );
  });
}
