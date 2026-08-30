import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('OTelResource', () {
    test('always sets service.name', () {
      final resource = OTelResource(serviceName: 'trueapp');
      expect(resource.attributes['service.name'], 'trueapp');
      expect(resource.serviceName, 'trueapp');
    });

    test('includes optional well-known attributes only when provided', () {
      final withoutOptional = OTelResource(serviceName: 'trueapp');
      expect(
          withoutOptional.attributes.containsKey('service.version'), isFalse);
      expect(
        withoutOptional.attributes.containsKey('deployment.environment'),
        isFalse,
      );

      final withOptional = OTelResource(
        serviceName: 'trueapp',
        serviceVersion: '1.2.3',
        deploymentEnvironment: 'production',
      );
      expect(withOptional.attributes['service.version'], '1.2.3');
      expect(withOptional.attributes['deployment.environment'], 'production');
    });

    test('merges extra attributes alongside well-known ones', () {
      final resource = OTelResource(
        serviceName: 'trueapp',
        attributes: {'device.model': 'iPhone17,1'},
      );
      expect(resource.attributes['service.name'], 'trueapp');
      expect(resource.attributes['device.model'], 'iPhone17,1');
    });

    test('extra attributes can override well-known ones', () {
      final resource = OTelResource(
        serviceName: 'trueapp',
        attributes: {'service.name': 'overridden'},
      );
      expect(resource.attributes['service.name'], 'overridden');
    });

    test('attributes map is unmodifiable', () {
      final resource = OTelResource(serviceName: 'trueapp');
      expect(() => resource.attributes['x'] = 'y', throwsUnsupportedError);
    });
  });
}
