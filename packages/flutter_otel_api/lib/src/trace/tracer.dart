/// Minimal placeholder for the future traces signal.
///
/// This is intentionally tiny: it exists so the SDK facade and app code can
/// already reference `Tracer`/`TracerProvider` shapes, proving the core is
/// signal-agnostic, without committing to a full span API yet. It will grow
/// (start/end span, context propagation, etc.) when traces are implemented,
/// without needing to change [flutter_otel_api]'s logs types.
abstract class Tracer {
  /// The instrumentation scope name this tracer was obtained for.
  String get name;
}

/// No-op [Tracer] used until a real tracing SDK implementation exists.
class NoopTracer implements Tracer {
  const NoopTracer(this.name);

  @override
  final String name;
}
