/// Removes sensitive content from telemetry before it is exported.
///
/// Used by `RedactingLogRecordProcessor` and `RedactingSpanProcessor`.
abstract class Redactor {
  /// Returns [value] with sensitive substrings replaced.
  String redact(String value);

  /// Whether the whole value of an attribute named [key] must be dropped,
  /// regardless of what it contains.
  bool isSensitiveKey(String key);
}

/// The text that replaces redacted content.
const String redactedPlaceholder = '[REDACTED]';

/// A regular expression whose matches are replaced by [replacement].
///
/// [replacement] may reference capture groups as `$1`, `$2`, ... so a rule
/// can keep part of a match, such as the key of a `key=value` pair.
class RedactionRule {
  RedactionRule(this.pattern, {this.replacement = redactedPlaceholder});

  final RegExp pattern;
  final String replacement;

  String apply(String value) => value.replaceAllMapped(
        pattern,
        (match) => replacement.replaceAllMapped(
          _groupReference,
          (ref) => match.group(int.parse(ref.group(1)!)) ?? '',
        ),
      );

  static final _groupReference = RegExp(r'\$(\d+)');
}

/// A [Redactor] driven by [RedactionRule]s and a set of sensitive attribute
/// key fragments.
///
/// The defaults cover credentials in URLs, `Authorization` values, secret
/// `key=value` / `"key": "value"` pairs and standalone bearer/basic tokens.
/// Add app-specific formats through [extraRules].
class PatternRedactor implements Redactor {
  PatternRedactor({
    List<RedactionRule>? rules,
    List<RedactionRule> extraRules = const [],
    Set<String>? sensitiveKeys,
  })  : _rules = [...(rules ?? defaultRules), ...extraRules],
        _sensitiveKeys = {
          for (final key in sensitiveKeys ?? defaultSensitiveKeys)
            key.toLowerCase(),
        };

  final List<RedactionRule> _rules;
  final Set<String> _sensitiveKeys;

  static const _notRedacted = r'(?!\[REDACTED\])';
  static const _value = '$_notRedacted[^\\s"\',;&})\\]]+';

  /// Rules applied in order. `Authorization` runs before the standalone
  /// bearer/basic rule so its scheme is swallowed instead of redacted twice.
  static final List<RedactionRule> defaultRules = [
    RedactionRule(
      RegExp(
        r'\b([a-z][a-z0-9+.\-]*://)[^/\s:@]+:[^/\s@]+@',
        caseSensitive: false,
      ),
      replacement: r'$1[REDACTED]@',
    ),
    RedactionRule(
      RegExp(
        '(\\bauthorization["\']?\\s*[:=]\\s*["\']?)'
        '(?:(?:bearer|basic)\\s+)?$_value',
        caseSensitive: false,
      ),
      replacement: r'$1[REDACTED]',
    ),
    RedactionRule(
      RegExp(
        '(\\b\\w*(?:password|passwd|secret|token|api[_-]?key|apikey)'
        '["\']?\\s*[:=]\\s*["\']?)$_value',
        caseSensitive: false,
      ),
      replacement: r'$1[REDACTED]',
    ),
    RedactionRule(
      RegExp(
        '\\b(bearer|basic)\\s+$_notRedacted[A-Za-z0-9\\-._~+/]+=*',
        caseSensitive: false,
      ),
      replacement: r'$1 [REDACTED]',
    ),
  ];

  /// Attribute keys containing any of these fragments (case-insensitive)
  /// have their whole value replaced.
  static const Set<String> defaultSensitiveKeys = {
    'authorization',
    'cookie',
    'password',
    'passwd',
    'secret',
    'token',
    'api_key',
    'apikey',
  };

  @override
  String redact(String value) {
    var result = value;
    for (final rule in _rules) {
      result = rule.apply(result);
    }
    return result;
  }

  @override
  bool isSensitiveKey(String key) {
    final lower = key.toLowerCase();
    return _sensitiveKeys.any(lower.contains);
  }
}

/// Redacts every string in an attribute map, dropping values of sensitive
/// keys entirely. Lists are redacted element by element.
Map<String, Object?> redactAttributes(
  Map<String, Object?> attributes,
  Redactor redactor,
) =>
    {
      for (final entry in attributes.entries)
        entry.key: redactor.isSensitiveKey(entry.key)
            ? redactedPlaceholder
            : _redactValue(entry.value, redactor),
    };

Object? _redactValue(Object? value, Redactor redactor) => switch (value) {
      final String s => redactor.redact(s),
      final List<Object?> list => [
          for (final item in list) _redactValue(item, redactor),
        ],
      _ => value,
    };
