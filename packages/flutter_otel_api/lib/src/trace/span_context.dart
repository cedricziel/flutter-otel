/// Identifies a span within a trace: the trace it belongs to, its own ID,
/// and whether it originated in a different process (propagated in via a
/// remote parent) rather than being started locally.
class SpanContext {
  const SpanContext({
    required this.traceId,
    required this.spanId,
    this.isRemote = false,
  });

  /// 32 lowercase hex characters identifying the trace this span belongs to.
  final String traceId;

  /// 16 lowercase hex characters identifying this span.
  final String spanId;

  /// Whether this context was propagated in from a remote parent (e.g. via
  /// an incoming `traceparent` header) rather than created locally.
  final bool isRemote;

  static final RegExp _hexTraceId = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _hexSpanId = RegExp(r'^[0-9a-f]{16}$');

  /// Whether both IDs are present, correctly sized, lowercase hex, and not
  /// all-zero (an all-zero ID is the spec's explicit "invalid" sentinel).
  bool get isValid =>
      _hexTraceId.hasMatch(traceId) &&
      _hexSpanId.hasMatch(spanId) &&
      !_isAllZero(traceId) &&
      !_isAllZero(spanId);

  static bool _isAllZero(String hex) =>
      hex.codeUnits.every((unit) => unit == 0x30);

  @override
  String toString() =>
      'SpanContext(traceId: $traceId, spanId: $spanId, isRemote: $isRemote)';

  @override
  bool operator ==(Object other) =>
      other is SpanContext &&
      other.traceId == traceId &&
      other.spanId == spanId &&
      other.isRemote == isRemote;

  @override
  int get hashCode => Object.hash(traceId, spanId, isRemote);
}
