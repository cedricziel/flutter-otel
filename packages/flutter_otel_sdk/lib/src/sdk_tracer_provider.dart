import 'package:flutter_otel_api/flutter_otel_api.dart';

import 'sdk_tracer.dart';

/// Concrete [TracerProvider] backed by a single [SpanProcessor].
///
/// Caches vended tracers by a `(name, version)` compound key (a Dart
/// record), the same collision-free pattern `SdkLoggerProvider` uses,
/// rather than a delimiter-joined string that could collide across
/// differing name/version pairs.
class SdkTracerProvider implements TracerProvider {
  SdkTracerProvider({required this.processor});

  final SpanProcessor processor;

  final Map<(String, String?), Tracer> _tracers = {};

  @override
  Tracer getTracer({String name = 'flutter_otel', String? version}) {
    final key = (name, version);
    return _tracers.putIfAbsent(
      key,
      () => SdkTracer(name: name, version: version, processor: processor),
    );
  }

  @override
  Future<void> forceFlush() => processor.forceFlush();

  @override
  Future<void> shutdown() => processor.shutdown();
}
