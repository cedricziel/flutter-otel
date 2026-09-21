/// Minimal placeholder for the future metrics signal. See [Tracer] for the
/// rationale — this proves the core is signal-agnostic without committing
/// to a full instrument API (counters, histograms, ...) yet.
abstract class Meter {
  /// The instrumentation scope name this meter was obtained for.
  String get name;
}

/// No-op [Meter] used until a real metrics SDK implementation exists.
class NoopMeter implements Meter {
  const NoopMeter(this.name);

  @override
  final String name;
}
