import 'dart:async';
import 'dart:io';

import 'package:dart_otel_api/dart_otel_api.dart';

/// A [SpanProcessor] that exports every finished span immediately, one at a
/// time. Intended for development and tests, where seeing a span show up
/// right away matters more than batching efficiency.
class SimpleSpanProcessor implements SpanProcessor {
  SimpleSpanProcessor(this.exporter, this.resource);

  final SpanExporter exporter;
  final OTelResource resource;

  final List<Future<void>> _pending = [];
  bool _shutdown = false;

  @override
  void onEnd(SpanData span) {
    if (_shutdown) return;
    final future = _exportSafely([span]);
    _pending.add(future);
    unawaited(future.whenComplete(() => _pending.remove(future)));
  }

  Future<void> _exportSafely(List<SpanData> spans) async {
    try {
      final result = await exporter.export(spans, resource);
      if (!result.success) {
        stderr.writeln('flutter_otel: span export failed: ${result.error}');
      }
    } catch (e, stackTrace) {
      stderr.writeln('flutter_otel: span export threw: $e\n$stackTrace');
    }
  }

  @override
  Future<void> forceFlush() => Future.wait(List<Future<void>>.of(_pending));

  @override
  Future<void> shutdown() async {
    _shutdown = true;
    await forceFlush();
    await exporter.shutdown();
  }
}
