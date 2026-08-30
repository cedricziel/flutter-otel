import 'dart:convert';

import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:http/http.dart' as http;

/// Exports [SpanData] as OTLP/HTTP with JSON encoding (the protobuf JSON
/// mapping), per the OpenTelemetry Protocol specification. No protobuf/
/// binary encoding is attempted — this exporter has no codegen dependency.
///
/// The [http.Client] is always injected, never constructed internally, so
/// exporter behavior is fully testable with `package:http/testing.dart`.
class OtlpHttpSpanExporter implements SpanExporter {
  OtlpHttpSpanExporter({
    required Uri endpoint,
    required http.Client httpClient,
    Map<String, String> headers = const {},
    bool ownsClient = false,
  })  : _endpoint = endpoint,
        _httpClient = httpClient,
        _headers = headers,
        _ownsClient = ownsClient;

  final Uri _endpoint;
  final http.Client _httpClient;
  final Map<String, String> _headers;

  /// Whether this exporter is responsible for closing [httpClient] on
  /// [shutdown]. `false` by default since the client is normally injected
  /// and owned by the caller; the SDK facade sets this to `true` for the
  /// client it default-constructs when no client is supplied in config.
  final bool _ownsClient;

  /// Resolves the effective traces endpoint per
  /// OTEL_EXPORTER_OTLP_*_ENDPOINT semantics: [tracesEndpoint] wins
  /// verbatim when set; otherwise `/v1/traces` is appended to
  /// [baseEndpoint]. Returns `null` when neither is set.
  static Uri? resolveTracesEndpoint({Uri? baseEndpoint, Uri? tracesEndpoint}) {
    if (tracesEndpoint != null) return tracesEndpoint;
    if (baseEndpoint == null) return null;
    final path = baseEndpoint.path.endsWith('/')
        ? baseEndpoint.path.substring(0, baseEndpoint.path.length - 1)
        : baseEndpoint.path;
    return baseEndpoint.replace(path: '$path/v1/traces');
  }

  @override
  Future<ExportResult> export(
    List<SpanData> spans,
    OTelResource resource,
  ) async {
    if (spans.isEmpty) return const ExportResult.success();
    try {
      final body = jsonEncode(_buildRequestBody(spans, resource));
      final response = await _httpClient.post(
        _endpoint,
        headers: {
          'Content-Type': 'application/json',
          ..._headers,
        },
        body: body,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const ExportResult.success();
      }
      return ExportResult.failure(
        'OTLP/HTTP export failed with status ${response.statusCode}: '
        '${response.body}',
      );
    } catch (e) {
      return ExportResult.failure(e);
    }
  }

  Map<String, Object?> _buildRequestBody(
    List<SpanData> spans,
    OTelResource resource,
  ) {
    final byScope = <_ScopeKey, List<SpanData>>{};
    for (final span in spans) {
      byScope
          .putIfAbsent(
            _ScopeKey(span.scopeName, span.scopeVersion),
            () => <SpanData>[],
          )
          .add(span);
    }

    return {
      'resourceSpans': [
        {
          'resource': {'attributes': encodeAttributes(resource.attributes)},
          'scopeSpans': [
            for (final entry in byScope.entries)
              {
                'scope': {
                  'name': entry.key.name,
                  if (entry.key.version != null) 'version': entry.key.version,
                },
                'spans': [
                  for (final span in entry.value) _encodeSpan(span),
                ],
              },
          ],
        },
      ],
    };
  }

  Map<String, Object?> _encodeSpan(SpanData span) => {
        'traceId': span.spanContext.traceId,
        'spanId': span.spanContext.spanId,
        if (span.parentSpanId != null) 'parentSpanId': span.parentSpanId,
        'name': span.name,
        'kind': _encodeKind(span.kind),
        'startTimeUnixNano': _toUnixNano(span.startTime).toString(),
        'endTimeUnixNano': _toUnixNano(span.endTime).toString(),
        'attributes': encodeAttributes(span.attributes),
        'events': [
          for (final event in span.events)
            {
              'timeUnixNano': _toUnixNano(event.timestamp).toString(),
              'name': event.name,
              'attributes': encodeAttributes(event.attributes),
            },
        ],
        'status': {
          'code': _encodeStatusCode(span.statusCode),
          if (span.statusDescription != null) 'message': span.statusDescription,
        },
      };

  /// Maps [SpanKind] 1:1 to OTLP's `Span.SpanKind` enum
  /// (UNSPECIFIED=0, INTERNAL=1, SERVER=2, CLIENT=3, PRODUCER=4,
  /// CONSUMER=5).
  int _encodeKind(SpanKind kind) => switch (kind) {
        SpanKind.internal => 1,
        SpanKind.server => 2,
        SpanKind.client => 3,
        SpanKind.producer => 4,
        SpanKind.consumer => 5,
      };

  /// Maps [StatusCode] 1:1 to OTLP's `Status.StatusCode` enum
  /// (UNSET=0, OK=1, ERROR=2).
  int _encodeStatusCode(StatusCode code) => switch (code) {
        StatusCode.unset => 0,
        StatusCode.ok => 1,
        StatusCode.error => 2,
      };

  int _toUnixNano(DateTime dateTime) =>
      dateTime.toUtc().microsecondsSinceEpoch * 1000;

  @override
  Future<void> shutdown() async {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}

class _ScopeKey {
  const _ScopeKey(this.name, this.version);

  final String name;
  final String? version;

  @override
  bool operator ==(Object other) =>
      other is _ScopeKey && other.name == name && other.version == version;

  @override
  int get hashCode => Object.hash(name, version);
}
