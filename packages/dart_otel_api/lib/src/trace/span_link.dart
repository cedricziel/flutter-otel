import 'span_context.dart';

/// A reference from a span to a causally related span that isn't its parent
/// — typically in a different trace.
///
/// Used to stitch together spans that shouldn't be nested under one another
/// (e.g. every message handled on a long-lived connection getting its own
/// root span, each linked back to the connection's span) so a backend can
/// still navigate between them without one trace growing for the entire
/// connection's lifetime.
class SpanLink {
  SpanLink(this.context, {Map<String, Object?> attributes = const {}})
      : attributes = Map.unmodifiable(attributes);

  /// The linked span's trace/span IDs.
  final SpanContext context;

  /// Structured attributes describing the link. Read-only.
  final Map<String, Object?> attributes;

  @override
  String toString() => 'SpanLink(context: $context, attributes: $attributes)';
}
