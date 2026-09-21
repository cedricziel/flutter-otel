import 'package:dart_otel_api/dart_otel_api.dart';

/// Traces a long-lived connection (a WebSocket, a JSON-RPC socket) the way
/// messaging is traced.
///
/// Opening the connection is an HTTP client span for the upgrade. Everything
/// sent or received over it afterwards is a message: a producer span per
/// request, open until the peer answers, and a consumer span per server
/// event. Each is linked to the connection's span rather than nested under
/// it, so no trace grows for as long as the connection lives.
///
/// Only names, ids and error codes are ever recorded: the request method or
/// event type, the message id and the error code. Never params, results,
/// session identifiers or message text; this class is never handed a payload.
///
/// With a null tracer every call does nothing. A tracer that throws is
/// swallowed: telemetry never breaks the caller.
class MessagingConnectionTracer {
  /// [system] is the `messaging.system` value on every span.
  ///
  /// [skippedNames] are events that record no span at all, e.g. a per-chunk
  /// delta that would drown the events around it.
  ///
  /// [knownEvents], when given, is the allowlist of event names recorded
  /// as-is; any other event is recorded as `other`, so a server-controlled
  /// string cannot blow up the cardinality of span names. Request methods
  /// are chosen by the caller and are recorded as given.
  ///
  /// [jsonRpc] adds `rpc.system`, `rpc.jsonrpc.version` and `rpc.method` to
  /// request spans.
  MessagingConnectionTracer(
    this._tracer, {
    required this.system,
    this.skippedNames = const {},
    this.knownEvents,
    this.jsonRpc = false,
  });

  final Tracer? _tracer;
  final String system;
  final Set<String> skippedNames;
  final Set<String>? knownEvents;
  final bool jsonRpc;

  SpanContext? _connection;

  /// Runs [open] inside the client span for the connection upgrade, then
  /// links every later message to that span. [route] is the connection's
  /// `http.route`.
  Future<T> connecting<T>(
    Future<T> Function() open, {
    required String route,
  }) async {
    final tracer = _tracer;
    if (tracer == null) return open();
    final span = _guard(
      () => tracer.startSpan(
        'HTTP GET',
        kind: SpanKind.client,
        attributes: {'http.method': 'GET', 'http.route': route},
      ),
    );
    try {
      final result = await open();
      _guard(() {
        _connection = span?.spanContext;
        span
          ?..setAttribute('http.status_code', 101)
          ..setStatus(StatusCode.ok)
          ..end();
      });
      return result;
    } catch (error) {
      _guard(() {
        span
          ?..setAttribute('error.type', error.runtimeType.toString())
          ..setStatus(StatusCode.error)
          ..end();
      });
      rethrow;
    }
  }

  /// Starts the producer span of one request; end it with [finishRequest].
  /// Returns null when nothing is recorded.
  Span? startRequest(String name, Object id) =>
      _start('$name send', SpanKind.producer, {
        'messaging.system': system,
        'messaging.operation.type': 'send',
        'messaging.destination.name': name,
        'messaging.message.id': '$id',
        if (jsonRpc) ...{
          'rpc.system': 'jsonrpc',
          'rpc.jsonrpc.version': '2.0',
          'rpc.method': name,
        },
      });

  /// Ends a request's span: with [errorCode] when the peer answered with a
  /// JSON-RPC error, with [failure] when there was no answer, else as a
  /// success.
  void finishRequest(Span? span, {int? errorCode, Object? failure}) {
    if (span == null) return;
    _guard(() {
      if (errorCode != null) {
        span.setAttribute('rpc.jsonrpc.error_code', errorCode);
      }
      if (failure != null) {
        span.setAttribute('error.type', failure.runtimeType.toString());
      }
      span
        ..setStatus(
          errorCode != null || failure != null
              ? StatusCode.error
              : StatusCode.ok,
        )
        ..end();
    });
  }

  /// Records a server event of the given [type] as an instant consumer span.
  void event(String type) {
    if (skippedNames.contains(type)) return;
    final allowed = knownEvents;
    final name = allowed == null || allowed.contains(type) ? type : 'other';
    final span = _start('$name receive', SpanKind.consumer, {
      'messaging.system': system,
      'messaging.operation.type': 'receive',
      'messaging.destination.name': name,
    });
    _guard(() {
      span
        ?..setStatus(StatusCode.ok)
        ..end();
    });
  }

  Span? _start(String name, SpanKind kind, Map<String, Object?> attributes) {
    final tracer = _tracer;
    if (tracer == null) return null;
    final connection = _connection;
    return _guard(
      () => tracer.startSpan(
        name,
        kind: kind,
        attributes: attributes,
        links: [if (connection != null) SpanLink(connection)],
      ),
    );
  }

  T? _guard<T>(T Function() body) {
    try {
      return body();
    } catch (_) {
      return null;
    }
  }
}
