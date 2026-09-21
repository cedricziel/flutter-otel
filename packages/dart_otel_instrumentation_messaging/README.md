# dart_otel_instrumentation_messaging

Messaging-style tracing for long-lived connections in flutter_otel: a
WebSocket, a JSON-RPC socket, anything that is opened once and then carries
many messages in both directions.

A `MessagingConnectionTracer` records:

- the connection upgrade as a `SpanKind.client` span named `HTTP GET`
  (`http.method`, `http.route`, `http.status_code` 101 on success, `error.type`
  on failure, which is rethrown),
- each request as a `SpanKind.producer` span named `<name> send`, open until
  you call `finishRequest` (`messaging.system`, `messaging.operation.type`
  `send`, `messaging.destination.name`, `messaging.message.id`, and
  `rpc.jsonrpc.error_code` / `error.type` when it failed),
- each server event as an instant `SpanKind.consumer` span named
  `<name> receive`.

Every message span is **linked** (a `SpanLink`) to the connection span
instead of nested under it, so no single trace grows for as long as the
connection lives, and a backend can still jump from a message to its
connection.

Pure Dart, depends only on `dart_otel_api`.

## What is recorded

Only names, ids and error codes: the request method or event type, the
message id and the JSON-RPC error code. The class never receives params,
results, session identifiers or message text, so none can end up on a span.
Event names are the one string a server controls, so give `knownEvents` an
allowlist and everything else is recorded as `other`.

## Failure behaviour

With a null tracer every call does nothing. A tracer or span that throws is
swallowed: telemetry never breaks the caller.

## Usage

```dart
import 'package:dart_otel_instrumentation_messaging/dart_otel_instrumentation_messaging.dart';

final messaging = MessagingConnectionTracer(
  tracer, // a Tracer?, e.g. OTelSdk.instance.getTracer(...); null records nothing
  system: 'my.gateway', // messaging.system
  skippedNames: {'message.delta'}, // no span for per-chunk events
  knownEvents: {'message.start', 'message.complete', 'tool.start'},
  jsonRpc: true, // adds rpc.system, rpc.jsonrpc.version, rpc.method
);

final socket = await messaging.connecting(
  () => WebSocket.connect(url),
  route: '/api/ws',
);

// Per request: a producer span, open until the answer arrives.
final span = messaging.startRequest('session.create', requestId);
try {
  await sendAndAwaitAnswer();
  messaging.finishRequest(span);
} on JsonRpcError catch (e) {
  messaging.finishRequest(span, errorCode: e.code);
} catch (e) {
  messaging.finishRequest(span, failure: e);
}

// Per server event: an instant consumer span.
socket.listen((message) => messaging.event(message.type));
```

`connecting` can be called again on reconnect; later messages link to the
newest successful connection.

## Options

| Option         | Meaning                                                                     |
| -------------- | --------------------------------------------------------------------------- |
| `system`       | `messaging.system` on every span (required).                                |
| `skippedNames` | Event names that record no span. Default: none.                             |
| `knownEvents`  | Allowlist of event names recorded as-is, the rest as `other`. Default: any. |
| `jsonRpc`      | Adds the `rpc.*` attributes to request spans. Default: `false`.             |

`route` (the connection's `http.route`) is given per `connecting` call.

## Testing

```bash
cd packages/dart_otel_instrumentation_messaging
dart analyze
dart test
```
