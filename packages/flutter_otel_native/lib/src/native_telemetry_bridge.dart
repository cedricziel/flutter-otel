import 'package:flutter/services.dart';
import 'package:flutter_otel_api/flutter_otel_api.dart';

import 'native_record_codec.dart';

/// Counts from one [NativeTelemetryBridge.drainAndForward] call.
class NativeDrainResult {
  const NativeDrainResult({
    required this.recordsIngested,
    required this.recordsSkipped,
    required this.recordsDropped,
  });

  /// How many drained lines were successfully decoded and ingested.
  final int recordsIngested;

  /// How many drained lines failed to decode (invalid JSON, unrecognized
  /// `kind`, or a missing required field) and were skipped.
  final int recordsSkipped;

  /// How many records native evicted from its on-disk queue (past its
  /// cap) since the previous drain, as reported by native itself.
  final int recordsDropped;
}

/// Dart-side bridge to `flutter_otel_native`'s Swift plugin: drains its
/// on-disk record queue over a [MethodChannel] and forwards each decoded
/// record into an existing [TracerProvider]/[LoggerProvider] pipeline.
class NativeTelemetryBridge {
  NativeTelemetryBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('flutter_otel_native');

  final MethodChannel _channel;

  /// Drains the native queue and forwards every decodable record into
  /// [tracerProvider]/[loggerProvider]. Never throws on malformed native
  /// data — malformed lines are counted in the result instead.
  Future<NativeDrainResult> drainAndForward({
    required TracerProvider tracerProvider,
    required LoggerProvider loggerProvider,
  }) async {
    final response =
        await _channel.invokeMapMethod<String, Object?>('drainQueue');
    final lines =
        (response?['records'] as List?)?.cast<String>() ?? const <String>[];
    final dropped = response?['droppedSinceLastDrain'] as int? ?? 0;

    var ingested = 0;
    var skipped = 0;
    for (final line in lines) {
      switch (decodeNativeRecordLine(line)) {
        case NativeSpanRecord(:final spanData):
          tracerProvider.ingestSpan(spanData);
          ingested++;
        case NativeLogRecord(:final logRecord):
          loggerProvider.ingestLogRecord(logRecord);
          ingested++;
        case null:
          skipped++;
      }
    }

    return NativeDrainResult(
      recordsIngested: ingested,
      recordsSkipped: skipped,
      recordsDropped: dropped,
    );
  }

  /// Tags subsequent native records with [sessionId] as a `session.id`
  /// attribute. Call once at startup and again whenever the session rolls.
  Future<void> setSessionId(String sessionId) =>
      _channel.invokeMethod('setSessionId', {'sessionId': sessionId});

  /// Tells native the currently active trace/span, so a native record
  /// taken moments later attaches as its child by default instead of
  /// starting a new root.
  Future<void> setCurrentTraceContext(SpanContext context) =>
      _channel.invokeMethod('setCurrentTraceContext', {
        'traceId': context.traceId,
        'spanId': context.spanId,
      });

  /// Clears whatever [setCurrentTraceContext] last set.
  Future<void> clearCurrentTraceContext() =>
      _channel.invokeMethod('clearCurrentTraceContext');

  /// Which channel distributed the running build — `"testflight"`,
  /// `"production"`, or `"unknown"` — per native's check of the app's
  /// StoreKit receipt. Never throws: a missing platform implementation
  /// (e.g. this plugin not registered, or a platform other than
  /// iOS/macOS) resolves to `"unknown"`, since telemetry enrichment must
  /// never be able to break the app.
  Future<String> distributionEnvironment() async {
    try {
      final result =
          await _channel.invokeMethod<String>('distributionEnvironment');
      return result ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }
}
