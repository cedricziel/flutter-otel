import 'package:flutter_otel_api/flutter_otel_api.dart';

/// A [TracerProvider] test double that records every span passed to
/// [ingestSpan] instead of exporting it anywhere.
class FakeTracerProvider implements TracerProvider {
  final List<SpanData> ingestedSpans = [];

  @override
  void ingestSpan(SpanData span) => ingestedSpans.add(span);

  @override
  Tracer getTracer({String name = 'flutter_otel', String? version}) =>
      NoopTracer(name);

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
