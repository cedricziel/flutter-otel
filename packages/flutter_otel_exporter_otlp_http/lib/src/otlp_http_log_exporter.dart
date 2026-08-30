import 'dart:convert';

import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:http/http.dart' as http;

/// Exports [LogRecord]s as OTLP/HTTP with JSON encoding (the protobuf JSON
/// mapping), per the OpenTelemetry Protocol specification. No protobuf/
/// binary encoding is attempted — this exporter has no codegen dependency.
///
/// The [http.Client] is always injected, never constructed internally, so
/// exporter behavior is fully testable with `package:http/testing.dart`.
class OtlpHttpLogExporter implements LogRecordExporter {
  OtlpHttpLogExporter({
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

  /// Resolves the effective logs endpoint per OTEL_EXPORTER_OTLP_*_ENDPOINT
  /// semantics: [logsEndpoint] wins verbatim when set; otherwise `/v1/logs`
  /// is appended to [baseEndpoint]. Returns `null` when neither is set.
  static Uri? resolveLogsEndpoint({Uri? baseEndpoint, Uri? logsEndpoint}) {
    if (logsEndpoint != null) return logsEndpoint;
    if (baseEndpoint == null) return null;
    final path = baseEndpoint.path.endsWith('/')
        ? baseEndpoint.path.substring(0, baseEndpoint.path.length - 1)
        : baseEndpoint.path;
    return baseEndpoint.replace(path: '$path/v1/logs');
  }

  @override
  Future<ExportResult> export(
    List<LogRecord> records,
    OTelResource resource,
  ) async {
    if (records.isEmpty) return const ExportResult.success();
    try {
      final body = jsonEncode(_buildRequestBody(records, resource));
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
    List<LogRecord> records,
    OTelResource resource,
  ) {
    final byScope = <_ScopeKey, List<LogRecord>>{};
    for (final record in records) {
      byScope
          .putIfAbsent(
            _ScopeKey(record.scopeName, record.scopeVersion),
            () => <LogRecord>[],
          )
          .add(record);
    }

    return {
      'resourceLogs': [
        {
          'resource': {'attributes': encodeAttributes(resource.attributes)},
          'scopeLogs': [
            for (final entry in byScope.entries)
              {
                'scope': {
                  'name': entry.key.name,
                  if (entry.key.version != null) 'version': entry.key.version,
                },
                'logRecords': [
                  for (final record in entry.value) _encodeLogRecord(record),
                ],
              },
          ],
        },
      ],
    };
  }

  Map<String, Object?> _encodeLogRecord(LogRecord record) => {
        'timeUnixNano': _toUnixNano(record.timestamp).toString(),
        'observedTimeUnixNano':
            _toUnixNano(record.observedTimestamp).toString(),
        'severityNumber': record.severity.severityNumber,
        'severityText': record.severity.severityText,
        'body': {'stringValue': record.body},
        'attributes': encodeAttributes(record.attributes),
        if (record.traceId != null) 'traceId': record.traceId,
        if (record.spanId != null) 'spanId': record.spanId,
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
