import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:flutter_otel_instrumentation_messaging/flutter_otel_instrumentation_messaging.dart';
import 'package:test/test.dart';

import 'support/recording_tracer.dart';

void main() {
  late RecordingTracer tracer;
  late MessagingConnectionTracer messaging;

  MessagingConnectionTracer build({
    Set<String> skippedNames = const {'message.delta'},
    Set<String>? knownEvents = const {'tool.start', 'message.complete'},
    bool jsonRpc = true,
  }) =>
      MessagingConnectionTracer(
        tracer,
        system: 'test.gateway',
        skippedNames: skippedNames,
        knownEvents: knownEvents,
        jsonRpc: jsonRpc,
      );

  setUp(() {
    tracer = RecordingTracer();
    messaging = build();
  });

  Future<void> connected() => messaging.connecting(() async {}, route: '/ws');

  RecordingSpan spanNamed(String name) =>
      tracer.spans.singleWhere((s) => s.name == name);

  group('the connection', () {
    test('is an HTTP client span for the upgrade', () async {
      await connected();

      final span = spanNamed('HTTP GET');
      expect(span.kind, SpanKind.client);
      expect(span.attributes, {
        'http.method': 'GET',
        'http.route': '/ws',
        'http.status_code': 101,
      });
      expect(span.status, StatusCode.ok);
      expect(span.ended, isTrue);
    });

    test('returns what the upgrade returns', () async {
      expect(await messaging.connecting(() async => 7, route: '/ws'), 7);
    });

    test('records a failed upgrade by error type and rethrows', () async {
      await expectLater(
        messaging.connecting<void>(
          () async => throw StateError('nope'),
          route: '/ws',
        ),
        throwsStateError,
      );

      final span = spanNamed('HTTP GET');
      expect(span.attributes['error.type'], 'StateError');
      expect(span.status, StatusCode.error);
      expect(span.ended, isTrue);
    });

    test('a failed upgrade is not linked to by later messages', () async {
      await expectLater(
        messaging.connecting<void>(
          () async => throw StateError('nope'),
          route: '/ws',
        ),
        throwsStateError,
      );

      messaging.event('tool.start');

      expect(spanNamed('tool.start receive').links, isEmpty);
    });

    test('a reconnect links later messages to the newest connection', () async {
      await connected();
      await connected();
      messaging.event('tool.start');

      final connections = tracer.spans.where((s) => s.name == 'HTTP GET');
      expect(
        spanNamed('tool.start receive').links.single.context,
        connections.last.spanContext,
      );
    });
  });

  group('a request', () {
    test(
        'is a producer span, open until answered, linked to the '
        'connection', () async {
      await connected();

      final span = messaging.startRequest('session.create', 1)!;
      final recorded = spanNamed('session.create send');
      expect(recorded.kind, SpanKind.producer);
      expect(recorded.ended, isFalse);
      expect(
        recorded.links.single.context,
        spanNamed('HTTP GET').spanContext,
      );
      expect(recorded.attributes, {
        'messaging.system': 'test.gateway',
        'messaging.operation.type': 'send',
        'messaging.destination.name': 'session.create',
        'messaging.message.id': '1',
        'rpc.system': 'jsonrpc',
        'rpc.jsonrpc.version': '2.0',
        'rpc.method': 'session.create',
      });

      messaging.finishRequest(span);

      expect(recorded.status, StatusCode.ok);
      expect(recorded.ended, isTrue);
    });

    test('leaves out the rpc attributes unless configured for JSON-RPC', () {
      messaging = build(jsonRpc: false);

      messaging.startRequest('session.create', 1);

      expect(spanNamed('session.create send').attributes.keys, {
        'messaging.system',
        'messaging.operation.type',
        'messaging.destination.name',
        'messaging.message.id',
      });
    });

    test('is not linked before any connection succeeded', () {
      messaging.startRequest('session.create', 1);

      expect(spanNamed('session.create send').links, isEmpty);
    });

    test('an error code marks the span failed and is recorded', () {
      final span = messaging.startRequest('prompt.submit', 1);

      messaging.finishRequest(span, errorCode: 4009);

      final recorded = spanNamed('prompt.submit send');
      expect(recorded.attributes['rpc.jsonrpc.error_code'], 4009);
      expect(recorded.status, StatusCode.error);
      expect(recorded.ended, isTrue);
    });

    test('a failure without an answer is recorded by error type', () {
      final span = messaging.startRequest('prompt.submit', 1);

      messaging.finishRequest(span, failure: StateError('closed'));

      final recorded = spanNamed('prompt.submit send');
      expect(recorded.attributes['error.type'], 'StateError');
      expect(recorded.status, StatusCode.error);
      expect(recorded.ended, isTrue);
    });

    test('finishing a request that never started does nothing', () {
      expect(() => messaging.finishRequest(null), returnsNormally);
    });
  });

  group('server events', () {
    test('are instant consumer spans linked to the connection', () async {
      await connected();

      messaging.event('tool.start');

      final span = spanNamed('tool.start receive');
      expect(span.kind, SpanKind.consumer);
      expect(span.ended, isTrue);
      expect(span.status, StatusCode.ok);
      expect(span.links.single.context, spanNamed('HTTP GET').spanContext);
      expect(span.attributes, {
        'messaging.system': 'test.gateway',
        'messaging.operation.type': 'receive',
        'messaging.destination.name': 'tool.start',
      });
    });

    test('leave out the skipped names', () {
      messaging.event('message.delta');
      messaging.event('message.delta');

      expect(tracer.spans, isEmpty);
    });

    test('name an unfamiliar type "other"', () {
      messaging.event('something.new');

      expect(
        spanNamed('other receive').attributes['messaging.destination.name'],
        'other',
      );
    });

    test('keep every name when there is no allowlist', () {
      messaging = build(knownEvents: null);

      messaging.event('something.new');

      expect(spanNamed('something.new receive'), isNotNull);
    });
  });

  test('a broken tracer never breaks the caller', () async {
    final broken = MessagingConnectionTracer(
      ThrowingTracer(),
      system: 'test.gateway',
    );

    expect(await broken.connecting(() async => 1, route: '/ws'), 1);
    await expectLater(
      broken.connecting<void>(
        () async => throw StateError('nope'),
        route: '/ws',
      ),
      throwsStateError,
    );
    final span = broken.startRequest('session.create', 1);
    expect(span, isNull);
    expect(() => broken.finishRequest(span, errorCode: 1), returnsNormally);
    expect(() => broken.event('tool.start'), returnsNormally);
  });

  test('a span that throws on end never breaks the caller', () async {
    final tracer = _EndThrowsTracer();
    final broken = MessagingConnectionTracer(tracer, system: 'test.gateway');

    expect(await broken.connecting(() async => 1, route: '/ws'), 1);
    final span = broken.startRequest('session.create', 1);
    expect(() => broken.finishRequest(span), returnsNormally);
    expect(() => broken.event('tool.start'), returnsNormally);
  });

  test('without a tracer nothing is recorded and callers still work', () async {
    final quiet = MessagingConnectionTracer(null, system: 'test.gateway');

    expect(await quiet.connecting(() async => 7, route: '/ws'), 7);
    expect(quiet.startRequest('session.create', 1), isNull);
    expect(() => quiet.finishRequest(null), returnsNormally);
    expect(() => quiet.event('tool.start'), returnsNormally);
  });
}

class _EndThrowsTracer extends RecordingTracer {
  @override
  Span startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    SpanContext? parentContext,
    List<SpanLink> links = const [],
  }) =>
      _EndThrowsSpan(super.startSpan(name, kind: kind) as RecordingSpan);
}

class _EndThrowsSpan extends RecordingSpan {
  _EndThrowsSpan(RecordingSpan inner)
      : super(inner.name, inner.kind, inner.spanContext);

  @override
  void end([DateTime? endTime]) => throw StateError('end broke');
}
