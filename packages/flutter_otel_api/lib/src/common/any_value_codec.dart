/// Encoding helpers for the OTLP JSON "AnyValue" mapping.
///
/// These live in the signal-agnostic core because every OTLP/HTTP exporter
/// (logs today, traces/metrics later) needs to encode attribute maps the
/// same way.
library;

/// Encodes a single attribute value as an OTLP JSON `AnyValue`.
///
/// - [String] -> `stringValue`
/// - [bool] -> `boolValue`
/// - [int] -> `intValue` (as a string, per the protobuf JSON mapping for
///   64-bit integers)
/// - [double] -> `doubleValue`
/// - anything else -> `stringValue` via `toString()`
Map<String, Object?> encodeAnyValue(Object? value) {
  if (value is String) return {'stringValue': value};
  if (value is bool) return {'boolValue': value};
  if (value is int) return {'intValue': value.toString()};
  if (value is double) return {'doubleValue': value};
  return {'stringValue': value.toString()};
}

/// Encodes an attribute map as an OTLP JSON `repeated KeyValue` list.
List<Map<String, Object?>> encodeAttributes(Map<String, Object?> attributes) =>
    attributes.entries
        .map(
            (entry) => {'key': entry.key, 'value': encodeAnyValue(entry.value)})
        .toList(growable: false);
