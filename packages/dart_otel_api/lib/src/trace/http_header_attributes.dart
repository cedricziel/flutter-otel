/// Span attributes for HTTP headers, named per the OpenTelemetry HTTP
/// semantic conventions (`http.request.header.<key>` and
/// `http.response.header.<key>`, each a string array), for use by HTTP
/// client and server instrumentation.
library;

/// Recorded in place of the value of a header that may carry credentials.
const String redactedHttpHeaderValue = '[REDACTED]';

const List<String> _sensitiveNameFragments = [
  'authorization',
  'cookie',
  'token',
  'secret',
  'password',
  'credential',
  'api-key',
  'apikey',
];

/// Whether the (lowercase) header [name] may carry credentials, so its value
/// must not be exported.
bool isSensitiveHttpHeader(String name) {
  final lower = name.toLowerCase();
  return _sensitiveNameFragments.any(lower.contains);
}

/// Attributes for the request [headers], keyed `http.request.header.<key>`.
///
/// Every header is captured; values of headers for which [redact] returns
/// `true` (default [isSensitiveHttpHeader]) are replaced with
/// [redactedHttpHeaderValue]. [redact] receives the lowercase header name.
Map<String, Object?> httpRequestHeaderAttributes(
  Map<String, String> headers, {
  bool Function(String name)? redact,
}) =>
    _headerAttributes('http.request.header', headers, redact);

/// Like [httpRequestHeaderAttributes], for the response [headers], keyed
/// `http.response.header.<key>`.
Map<String, Object?> httpResponseHeaderAttributes(
  Map<String, String> headers, {
  bool Function(String name)? redact,
}) =>
    _headerAttributes('http.response.header', headers, redact);

Map<String, Object?> _headerAttributes(
  String prefix,
  Map<String, String> headers,
  bool Function(String name)? redact,
) {
  final shouldRedact = redact ?? isSensitiveHttpHeader;
  return {
    for (final entry in headers.entries)
      '$prefix.${_attributeKey(entry.key)}': [
        shouldRedact(entry.key.toLowerCase())
            ? redactedHttpHeaderValue
            : entry.value,
      ],
  };
}

/// The semantic conventions lowercase the header name and replace `-` with
/// `_` to form the attribute key.
String _attributeKey(String headerName) =>
    headerName.toLowerCase().replaceAll('-', '_');
