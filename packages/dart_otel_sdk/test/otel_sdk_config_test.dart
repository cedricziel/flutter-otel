import 'package:dart_otel_sdk/dart_otel_sdk.dart';
import 'package:test/test.dart';

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

  group('OTelSdkConfig console logging', () {
    test('is off by default and prints from debug up', () {
      final config = OTelSdkConfig(resource: resource());

      expect(config.consoleLogging, isFalse);
      expect(config.consoleLogSeverity, LogSeverity.debug);
    });

    test('accepts explicit values', () {
      final config = OTelSdkConfig(
        resource: resource(),
        consoleLogging: true,
        consoleLogSeverity: LogSeverity.warn,
      );

      expect(config.consoleLogging, isTrue);
      expect(config.consoleLogSeverity, LogSeverity.warn);
    });
  });

  group('OTelSdkConfig redaction', () {
    test('has no redactor by default', () {
      expect(OTelSdkConfig(resource: resource()).redactor, isNull);
    });

    test('keeps the redactor it is given', () {
      final redactor = PatternRedactor();
      final config = OTelSdkConfig(resource: resource(), redactor: redactor);

      expect(config.redactor, same(redactor));
    });
  });
}
