import 'dart:async';

import 'package:flutter_otel_sdk/flutter_otel_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_span_exporter.dart';

void main() {
  late FakeSpanExporter exporter;
  late OTelResource resource;
  late SimpleSpanProcessor processor;

  setUp(() {
    exporter = FakeSpanExporter();
    resource = OTelResource(serviceName: 'test');
    processor = SimpleSpanProcessor(exporter, resource);
  });

  group('SdkTracerProvider.getTracer', () {
    test('returns the same Tracer instance for the same name/version', () {
      final provider = SdkTracerProvider(processor: processor);

      final a = provider.getTracer(name: 'foo', version: '1.0.0');
      final b = provider.getTracer(name: 'foo', version: '1.0.0');
      final c = provider.getTracer(name: 'bar');

      expect(identical(a, b), isTrue);
      expect(identical(a, c), isFalse);
    });

    test(
        'does not collide for name/version pairs that would collide under a '
        'delimiter-joined string key', () {
      final provider = SdkTracerProvider(processor: processor);

      // Both of these would join to the same string under a naive
      // '$name:$version' (or '$name@$version') cache key.
      final a = provider.getTracer(name: 'a:b', version: 'c');
      final b = provider.getTracer(name: 'a', version: 'b:c');

      expect(identical(a, b), isFalse);
    });

    test('stamps the requested name onto the returned tracer', () {
      final provider = SdkTracerProvider(processor: processor);
      final tracer = provider.getTracer(name: 'my.scope', version: '9.9.9');

      expect(tracer.name, 'my.scope');
    });
  });

  group('SdkTracerProvider.forceFlush/shutdown', () {
    test('delegate to the processor', () async {
      final provider = SdkTracerProvider(processor: processor);

      provider.getTracer().startSpan('op').end();
      await provider.forceFlush();
      expect(exporter.exportedBatches, hasLength(1));

      await provider.shutdown();
      expect(exporter.shutdownCallCount, 1);
    });
  });

  group('SdkTracerProvider.ingestSpan', () {
    test(
        'does not export synchronously; forceFlush is required to observe '
        'it', () {
      final provider = SdkTracerProvider(processor: processor);
      exporter.gate = Completer<void>();
      final span = SpanData(
        name: 'native.op',
        spanContext: const SpanContext(
          traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
          spanId: '00f067aa0ba902b7',
        ),
        startTime: DateTime.now(),
        endTime: DateTime.now(),
      );

      provider.ingestSpan(span);

      expect(exporter.allSpans, isEmpty);
    });

    test('the ingested span is exported after forceFlush', () async {
      final provider = SdkTracerProvider(processor: processor);
      final span = SpanData(
        name: 'native.op',
        spanContext: const SpanContext(
          traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
          spanId: '00f067aa0ba902b7',
        ),
        startTime: DateTime.now(),
        endTime: DateTime.now(),
      );

      provider.ingestSpan(span);
      await provider.forceFlush();

      expect(exporter.allSpans, [same(span)]);
    });
  });
}
