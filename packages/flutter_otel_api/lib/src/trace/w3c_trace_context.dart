/// Encoding/decoding for the W3C Trace Context `traceparent` header
/// (https://www.w3.org/TR/trace-context/), so an HTTP instrumentation
/// package can propagate the active trace across a process boundary.
///
/// `tracestate` is intentionally not handled: this SDK has no vendor-
/// specific state to carry and doesn't need to round-trip someone else's.
library;

import 'span_context.dart';

final RegExp _traceparentPattern = RegExp(
  r'^([0-9a-f]{2})-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$',
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
/// Returns `null` when [header] is missing, malformed (wrong number of
/// segments, wrong segment lengths, non-hex characters), version `ff` (a
/// reserved, always-invalid version per the spec), or carries an all-zero
/// trace ID or span ID.
SpanContext? parseTraceparent(String? header) {
  if (header == null) return null;
  final match = _traceparentPattern.firstMatch(header.trim());
  if (match == null) return null;

  final version = match.group(1)!;
  if (version == 'ff') return null;

  final context = SpanContext(
    traceId: match.group(2)!,
    spanId: match.group(3)!,
    isRemote: true,
  );
  if (!context.isValid) return null;
  return context;
}
