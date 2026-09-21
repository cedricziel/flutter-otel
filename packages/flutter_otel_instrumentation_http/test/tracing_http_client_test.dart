import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:flutter_otel_instrumentation_http/flutter_otel_instrumentation_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/recording_tracer.dart';

void main() {
  late RecordingTracer tracer;

  TracingHttpClient clientFor(
    http.Client inner, {
    String Function(String path)? routeTemplate,
    bool captureHeaders = true,
  }) =>
      TracingHttpClient(
        inner,
        tracerProvider: () => tracer,
        routeTemplate: routeTemplate,
        captureHeaders: captureHeaders,
      );

  setUp(() => tracer = RecordingTracer());

  test('starts a client span with http attributes and ends it', () async {
    final client = clientFor(MockClient((_) async => http.Response('', 200)));

    await client.get(Uri.parse('https://example.com/notes'));

    final span = tracer.spans.single;
    expect(span.name, 'GET /notes');
    expect(span.kind, SpanKind.client);
    expect(span.attributes['http.method'], 'GET');
    expect(span.attributes['http.target'], '/notes');
    expect(span.attributes['http.status_code'], 200);
    expect(span.ended, isTrue);
  });

  test('uses routeTemplate for the span name only', () async {
    final client = clientFor(
      MockClient((_) async => http.Response('', 200)),
      routeTemplate: (_) => '/notes/:id',
    );

    await client.get(Uri.parse('https://example.com/notes/01ABC'));

    final span = tracer.spans.single;
    expect(span.name, 'GET /notes/:id');
    expect(span.attributes['http.target'], '/notes/01ABC');
  });

  test('injects a traceparent header from the span context', () async {
    http.Request? captured;
    final client = clientFor(
      MockClient((request) async {
        captured = request;
        return http.Response('', 200);
      }),
    );

    await client.get(Uri.parse('https://example.com/notes'));

    expect(
      captured?.headers['traceparent'],
      formatTraceparent(tracer.spans.single.spanContext),
    );
  });

  test('captures request and response headers, redacting secrets', () async {
    final client = clientFor(
      MockClient(
        (_) async => http.Response(
          '',
          200,
          headers: {'content-type': 'application/json', 'set-cookie': 'sid=1'},
        ),
      ),
    );

    await client.get(
      Uri.parse('https://example.com/notes'),
      headers: {'Authorization': 'Bearer secret', 'Accept': 'application/json'},
    );

    final attrs = tracer.spans.single.attributes;
    expect(attrs['http.request.header.accept'], ['application/json']);
    expect(attrs['http.request.header.authorization'], [
      redactedHttpHeaderValue,
    ]);
    expect(attrs['http.request.header.traceparent'], isNotNull);
    expect(attrs['http.response.header.content_type'], ['application/json']);
    expect(attrs['http.response.header.set_cookie'], [
      redactedHttpHeaderValue,
    ]);
    expect(
      attrs.values.expand((v) => v is List ? v : [v]),
      isNot(contains('Bearer secret')),
    );
  });

  test('captures no headers when captureHeaders is false', () async {
    final client = clientFor(
      MockClient((_) async => http.Response('', 200)),
      captureHeaders: false,
    );

    await client.get(
      Uri.parse('https://example.com/notes'),
      headers: {'Accept': '*/*'},
    );

    expect(
      tracer.spans.single.attributes.keys.where((k) => k.contains('.header.')),
      isEmpty,
    );
  });

  test('marks a 5xx response as an error', () async {
    final client = clientFor(MockClient((_) async => http.Response('', 503)));

    await client.get(Uri.parse('https://example.com/notes'));

    expect(tracer.spans.single.status, StatusCode.error);
  });

  test('records the exception, sets error status and rethrows', () async {
    final client = clientFor(
      MockClient((_) async => throw Exception('network down')),
    );

    await expectLater(
      client.get(Uri.parse('https://example.com/notes')),
      throwsA(isA<Exception>()),
    );

    final span = tracer.spans.single;
    expect(span.status, StatusCode.error);
    expect(span.events, ['exception']);
    expect(span.ended, isTrue);
  });
}
