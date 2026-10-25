import 'dart:convert';

import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:http/http.dart' as http;

/// Exports [MetricData] as OTLP/HTTP with JSON encoding (the protobuf JSON
/// mapping), per the OpenTelemetry Protocol specification. All sums and
/// histograms are sent with cumulative aggregation temporality.
///
/// The [http.Client] is always injected, never constructed internally, so
/// exporter behavior is fully testable with `package:http/testing.dart`.
class OtlpHttpMetricExporter implements MetricExporter {
  OtlpHttpMetricExporter({
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

  /// Whether this exporter is responsible for closing the client on
  /// [shutdown]; see `OtlpHttpLogExporter`.
  final bool _ownsClient;

  /// OTLP `AGGREGATION_TEMPORALITY_CUMULATIVE`.
  static const int _cumulative = 2;

  /// Resolves the effective metrics endpoint per OTEL_EXPORTER_OTLP_*_ENDPOINT
  /// semantics: [metricsEndpoint] wins verbatim when set; otherwise
  /// `/v1/metrics` is appended to [baseEndpoint]. Returns `null` when neither
  /// is set.
  static Uri? resolveMetricsEndpoint(
      {Uri? baseEndpoint, Uri? metricsEndpoint}) {
    if (metricsEndpoint != null) return metricsEndpoint;
    if (baseEndpoint == null) return null;
    final path = baseEndpoint.path.endsWith('/')
        ? baseEndpoint.path.substring(0, baseEndpoint.path.length - 1)
        : baseEndpoint.path;
    return baseEndpoint.replace(path: '$path/v1/metrics');
  }

  @override
  Future<ExportResult> export(
    List<MetricData> metrics,
    OTelResource resource,
  ) async {
    if (metrics.isEmpty) return const ExportResult.success();
    try {
      final body = jsonEncode(_buildRequestBody(metrics, resource));
      final response = await _httpClient.post(
        _endpoint,
        headers: {
          ..._headers,
          'Content-Type': 'application/json',
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
    List<MetricData> metrics,
    OTelResource resource,
  ) {
    final byScope = <(String, String?), List<MetricData>>{};
    for (final metric in metrics) {
      byScope.putIfAbsent(
          (metric.scopeName, metric.scopeVersion), () => []).add(metric);
    }

    return {
      'resourceMetrics': [
        {
          'resource': {'attributes': encodeAttributes(resource.attributes)},
          'scopeMetrics': [
            for (final MapEntry(key: (name, version), value: scoped)
                in byScope.entries)
              {
                'scope': {
                  'name': name,
                  if (version != null) 'version': version
                },
                'metrics': [for (final metric in scoped) _encodeMetric(metric)],
              },
          ],
        },
      ],
    };
  }

  Map<String, Object?> _encodeMetric(MetricData metric) => {
        'name': metric.name,
        if (metric.description != null) 'description': metric.description,
        if (metric.unit != null) 'unit': metric.unit,
        ...switch (metric) {
          SumMetricData() => {
              'sum': {
                'dataPoints': metric.points.map(_encodeNumberPoint).toList(),
                'aggregationTemporality': _cumulative,
                'isMonotonic': metric.isMonotonic,
              },
            },
          GaugeMetricData() => {
              'gauge': {
                'dataPoints': metric.points.map(_encodeNumberPoint).toList(),
              },
            },
          HistogramMetricData() => {
              'histogram': {
                'dataPoints': metric.points.map(_encodeHistogramPoint).toList(),
                'aggregationTemporality': _cumulative,
              },
            },
        },
      };

  Map<String, Object?> _encodePoint(MetricDataPoint point) => {
        'attributes': encodeAttributes(point.attributes),
        'startTimeUnixNano': _toUnixNano(point.startTime).toString(),
        'timeUnixNano': _toUnixNano(point.time).toString(),
      };

  Map<String, Object?> _encodeNumberPoint(NumberDataPoint point) => {
        ..._encodePoint(point),
        ...switch (point.value) {
          final int value => {'asInt': value.toString()},
          final num value => {'asDouble': value.toDouble()},
        },
      };

  Map<String, Object?> _encodeHistogramPoint(HistogramDataPoint point) => {
        ..._encodePoint(point),
        'count': point.count.toString(),
        'sum': point.sum,
        'bucketCounts': [for (final c in point.bucketCounts) c.toString()],
        'explicitBounds': point.explicitBounds,
        if (point.min != null) 'min': point.min,
        if (point.max != null) 'max': point.max,
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
