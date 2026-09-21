/// The relationship between a span and its callers/callees, matching
/// OTel's `SpanKind`.
enum SpanKind {
  /// Default value. A span that doesn't cross a process boundary.
  internal,

  /// A span covering the server-side handling of an inbound request.
  server,

  /// A span covering an outbound request to another service.
  client,

  /// A span covering a message being sent to a broker/queue.
  producer,

  /// A span covering a message being received from a broker/queue.
  consumer,
}
