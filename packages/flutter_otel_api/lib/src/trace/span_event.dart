/// A timestamped event that occurred during a span's lifetime (e.g. an
/// exception, a cache miss, a milestone worth annotating).
class SpanEvent {
  SpanEvent({
    required this.name,
    DateTime? timestamp,
    Map<String, Object?> attributes = const {},
  })  : timestamp = timestamp ?? DateTime.now(),
        attributes = Map.unmodifiable(attributes);

  /// The event's name.
  final String name;

  /// When the event occurred. Defaults to `DateTime.now()` at construction
  /// time.
  final DateTime timestamp;

  /// Structured attributes attached to this event. Read-only.
  final Map<String, Object?> attributes;

  @override
  String toString() => 'SpanEvent(name: $name, attributes: $attributes)';
}
