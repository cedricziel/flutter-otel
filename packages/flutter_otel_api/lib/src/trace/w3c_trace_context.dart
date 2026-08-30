/// Encoding/decoding for the W3C Trace Context `traceparent` header
/// (https://www.w3.org/TR/trace-context/), so an HTTP instrumentation
/// package can propagate the active trace across a process boundary.
///
/// `tracestate` is intentionally not handled: this SDK has no vendor-
/// specific state to carry and doesn't need to round-trip someone else's.
library;

import 'span_context.dart';

/// Matches version `00` exactly: `00-traceId-spanId-flags` and nothing else.
/// Version `00` is not allowed to carry any trailing fields.
final RegExp _version00Pattern = RegExp(
  r'^00-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$',
);

/// Matches any other two-hex-digit version, extracting the same three known
/// fields but permitting (and ignoring) additional `-`-separated fields
/// appended after them, per the spec's forward-compatibility rule for
/// versions above `00`.
final RegExp _futureVersionPattern = RegExp(
  r'^([0-9a-f]{2})-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})(-.*)?$',
);

/// Formats [context] as a `traceparent` header value:
/// `00-<32 hex traceId>-<16 hex spanId>-<2 hex flags>`.
///
/// This SDK never samples — every span is always recorded — so the
/// `sampled` flag is always set (`01`).
String formatTraceparent(SpanContext context) =>
    '00-${context.traceId}-${context.spanId}-01';

/// Parses a `traceparent` header value into a remote [SpanContext]
/// (`isRemote: true`).
///
/// Per the W3C spec, version `00` is parsed strictly: it must be exactly the
/// 4-field `00-traceId-spanId-flags` shape with nothing appended. Versions
/// `01` through `fe` are parsed forward-compatibly: the known trace-id/
/// span-id/flags fields are extracted even if the sender appended extra
/// `-`-separated fields after them, since higher versions are allowed to
/// grow the header that way.
///
/// Returns `null` when [header] is missing, malformed (wrong number of
/// segments, wrong segment lengths, non-hex characters), version `ff` (a
/// reserved, always-invalid version per the spec), or carries an all-zero
/// trace ID or span ID.
SpanContext? parseTraceparent(String? header) {
  if (header == null) return null;
  final trimmed = header.trim();

  final exact = _version00Pattern.firstMatch(trimmed);
  if (exact != null) {
    return _toSpanContext(traceId: exact.group(1)!, spanId: exact.group(2)!);
  }

  final future = _futureVersionPattern.firstMatch(trimmed);
  if (future == null) return null;
  final version = future.group(1)!;
  if (version == '00' || version == 'ff') return null;

  return _toSpanContext(
    traceId: future.group(2)!,
    spanId: future.group(3)!,
  );
}

SpanContext? _toSpanContext({
  required String traceId,
  required String spanId,
}) {
  final context = SpanContext(traceId: traceId, spanId: spanId, isRemote: true);
  if (!context.isValid) return null;
  return context;
}
