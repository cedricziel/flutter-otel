/// Describes the entity producing telemetry: the app/service emitting logs,
/// traces, and (later) metrics. Shared by every signal, which is why it
/// lives in the signal-agnostic core.
class OTelResource {
  /// Builds a resource from well-known semantic-convention attributes plus
  /// any extra attributes the caller wants attached. Well-known keys
  /// (`service.name`, `service.version`, `deployment.environment`) are
  /// always present; [attributes] may add to or override them.
  factory OTelResource({
    required String serviceName,
    String? serviceVersion,
    String? deploymentEnvironment,
    Map<String, Object?> attributes = const {},
  }) {
    if (attributes.containsKey('service.name')) {
      final override = attributes['service.name'];
      if (override is! String) {
        throw ArgumentError.value(
          override,
          'attributes["service.name"]',
          'If attributes contains a "service.name" key, its value must be '
              'a non-null String.',
        );
      }
    }
    final merged = <String, Object?>{
      'service.name': serviceName,
      if (serviceVersion != null) 'service.version': serviceVersion,
      if (deploymentEnvironment != null)
        'deployment.environment': deploymentEnvironment,
      ...attributes,
    };
    return OTelResource._(Map.unmodifiable(merged));
  }

  const OTelResource._(this.attributes);

  /// The fully-resolved, read-only set of resource attributes.
  final Map<String, Object?> attributes;

  /// Convenience accessor for the `service.name` attribute, which is always
  /// present.
  String get serviceName => attributes['service.name']! as String;

  @override
  String toString() => 'OTelResource($attributes)';
}
