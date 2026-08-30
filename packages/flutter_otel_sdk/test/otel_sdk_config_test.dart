import 'package:flutter_otel_sdk/flutter_otel_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OTelResource resource() => OTelResource(serviceName: 'test');

  group('OTelSdkConfig validation', () {
    test('accepts valid positive values', () {
      expect(
        () => OTelSdkConfig(
          resource: resource(),
          maxQueueSize: 1,
          maxExportBatchSize: 1,
          scheduledDelay: const Duration(milliseconds: 1),
        ),
        returnsNormally,
      );
    });

    test('throws ArgumentError when maxQueueSize is zero', () {
      expect(
        () => OTelSdkConfig(resource: resource(), maxQueueSize: 0),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when maxQueueSize is negative', () {
      expect(
        () => OTelSdkConfig(resource: resource(), maxQueueSize: -1),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when maxExportBatchSize is zero', () {
      expect(
        () => OTelSdkConfig(resource: resource(), maxExportBatchSize: 0),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when maxExportBatchSize is negative', () {
      expect(
        () => OTelSdkConfig(resource: resource(), maxExportBatchSize: -5),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when scheduledDelay is Duration.zero', () {
      expect(
        () => OTelSdkConfig(
          resource: resource(),
          scheduledDelay: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when scheduledDelay is negative', () {
      expect(
        () => OTelSdkConfig(
          resource: resource(),
          scheduledDelay: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    });
  });
}
