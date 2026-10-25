import 'package:flutter_otel/flutter_otel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_logger.dart';

void main() {
  test('logs an event as an info record with its attributes', () {
    final logger = RecordingLogger();

    appEventLogger(logger)('auth.state', {'state': 'ready'});

    final record = logger.records.single;
    expect(record.body, 'auth.state');
    expect(record.severity, LogSeverity.info);
    expect(record.attributes, {'state': 'ready'});
  });

  test('never throws when the logger breaks', () {
    expect(
      () => appEventLogger(ThrowingLogger())('auth.state'),
      returnsNormally,
    );
  });

  test('the no-op logger accepts events and records nothing', () {
    expect(() => noopAppEventLogger('auth.state', {'state': 'ready'}),
        returnsNormally);
  });
}
