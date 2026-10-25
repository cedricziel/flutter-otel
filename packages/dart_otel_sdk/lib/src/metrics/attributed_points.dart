import 'package:dart_otel_api/dart_otel_api.dart';

/// The attribute set that collects measurements dropped by the cardinality
/// limit.
const Map<String, Object?> overflowAttributes = {'otel.metric.overflow': true};

/// Per-attribute-set state of one instrument, capped at [maxCardinality]
/// distinct sets.
///
/// Once the cap is reached, new attribute sets share a single overflow entry
/// (counted against the cap) so a runaway attribute cannot grow memory
/// without bound.
class AttributedPoints<V> {
  AttributedPoints(this.maxCardinality);

  final int maxCardinality;
  final Map<String, (Map<String, Object?>, V)> _entries = {};

  bool get isEmpty => _entries.isEmpty;

  Iterable<(Map<String, Object?>, V)> get entries => _entries.values;

  /// Returns the state for [attributes], creating it with [create] on first
  /// use.
  V of(MetricAttributes attributes, V Function() create) {
    var key = _keyOf(attributes);
    var stored = attributes;
    if (!_entries.containsKey(key) && _entries.length >= maxCardinality - 1) {
      key = _keyOf(overflowAttributes);
      stored = overflowAttributes;
    }
    return (_entries[key] ??= (Map.unmodifiable(stored), create())).$2;
  }

  // Sorted so key order does not matter; the type tag keeps 1 and '1' apart.
  static String _keyOf(MetricAttributes attributes) {
    if (attributes.isEmpty) return '';
    final keys = attributes.keys.toList()..sort();
    return keys
        .map(
            (k) => '$k\u0000${attributes[k].runtimeType}\u0000${attributes[k]}')
        .join('\u0001');
  }
}
