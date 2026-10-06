/// Coarse, non-identifying device attributes for OpenTelemetry resources,
/// and an opt-in, vendor-scoped installation ID.
library;

export 'src/device_attributes.dart'
    show describeAndroid, describeApple, describeDevice, detectDeviceAttributes;
export 'src/installation_id.dart' show detectAppInstallationId;
