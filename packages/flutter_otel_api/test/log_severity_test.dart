import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:test/test.dart';

void main() {
  group('LogSeverity', () {
    test('maps each severity to the first number in its OTel range', () {
      expect(LogSeverity.trace.severityNumber, 1);
      expect(LogSeverity.debug.severityNumber, 5);
      expect(LogSeverity.info.severityNumber, 9);
      expect(LogSeverity.warn.severityNumber, 13);
      expect(LogSeverity.error.severityNumber, 17);
      expect(LogSeverity.fatal.severityNumber, 21);
    });

    test('maps each severity to its OTel severityText', () {
      expect(LogSeverity.trace.severityText, 'TRACE');
      expect(LogSeverity.debug.severityText, 'DEBUG');
      expect(LogSeverity.info.severityText, 'INFO');
      expect(LogSeverity.warn.severityText, 'WARN');
      expect(LogSeverity.error.severityText, 'ERROR');
      expect(LogSeverity.fatal.severityText, 'FATAL');
    });

    test('severity numbers are strictly increasing in declaration order', () {
      final numbers = LogSeverity.values.map((s) => s.severityNumber).toList();
      for (var i = 1; i < numbers.length; i++) {
        expect(numbers[i], greaterThan(numbers[i - 1]));
      }
    });
  });
}
