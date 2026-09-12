import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:flutter_otel_native/src/native_record_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeNativeRecordLine', () {
    test('decodes a span line into a NativeSpanRecord', () {
      const line = '{"kind":"span","name":"app.launch.pre_engine",'
          '"traceId":"4bf92f3577b34da6a3ce929d0e0e4736",'
          '"spanId":"00f067aa0ba902b7","parentSpanId":null,'
          '"spanKind":"internal","startTimeUnixNano":"1700000000000000000",'
          '"endTimeUnixNano":"1700000000050000000",'
          '"attributes":{"os.name":"ios"},"events":[],'
          '"statusCode":"unset","scopeName":"flutter_otel_native",'
          '"scopeVersion":"0.1.0"}';

      final record = decodeNativeRecordLine(line);

      expect(record, isA<NativeSpanRecord>());
      final span = (record as NativeSpanRecord).spanData;
      expect(span.name, 'app.launch.pre_engine');
      expect(span.spanContext.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(span.spanContext.spanId, '00f067aa0ba902b7');
      expect(span.parentSpanId, isNull);
      expect(span.kind, SpanKind.internal);
      expect(span.attributes, {'os.name': 'ios'});
      expect(span.events, isEmpty);
      expect(span.statusCode, StatusCode.unset);
      expect(span.scopeName, 'flutter_otel_native');
      expect(span.scopeVersion, '0.1.0');
      expect(
        span.startTime.difference(
          DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ),
        Duration.zero,
      );
    });

    test('decodes a span line with a parent and an event', () {
      const line = '{"kind":"span","name":"child","traceId":'
          '"4bf92f3577b34da6a3ce929d0e0e4736","spanId":'
          '"00f067aa0ba902b7","parentSpanId":"a1b2c3d4e5f60708",'
          '"spanKind":"client","startTimeUnixNano":"1700000000000000000",'
          '"endTimeUnixNano":"1700000000050000000","attributes":{},'
          '"events":[{"name":"retry","timeUnixNano":"1700000000010000000",'
          '"attributes":{"attempt":1}}],"statusCode":"error",'
          '"statusDescription":"timed out","scopeName":"flutter_otel_native"}';

      final record = decodeNativeRecordLine(line) as NativeSpanRecord;
      final span = record.spanData;

      expect(span.parentSpanId, 'a1b2c3d4e5f60708');
      expect(span.kind, SpanKind.client);
      expect(span.statusCode, StatusCode.error);
      expect(span.statusDescription, 'timed out');
      expect(span.events, hasLength(1));
      expect(span.events.single.name, 'retry');
      expect(span.events.single.attributes, {'attempt': 1});
    });

    test('decodes a log line into a NativeLogRecord', () {
      const line = '{"kind":"log","timeUnixNano":"1700000000010000000",'
          '"severity":"warn","body":"native record",'
          '"attributes":{"count":3},'
          '"traceId":"4bf92f3577b34da6a3ce929d0e0e4736",'
          '"spanId":"00f067aa0ba902b7"}';

      final record = decodeNativeRecordLine(line);

      expect(record, isA<NativeLogRecord>());
      final log = (record as NativeLogRecord).logRecord;
      expect(log.body, 'native record');
      expect(log.severity, LogSeverity.warn);
      expect(log.attributes, {'count': 3});
      expect(log.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(log.spanId, '00f067aa0ba902b7');
    });

    test('decodes a log line with no trace context', () {
      const line = '{"kind":"log","timeUnixNano":"1700000000010000000",'
          '"severity":"info","body":"hello","attributes":{}}';

      final log = (decodeNativeRecordLine(line) as NativeLogRecord).logRecord;

      expect(log.traceId, isNull);
      expect(log.spanId, isNull);
    });

    test('returns null for invalid JSON', () {
      expect(decodeNativeRecordLine('not json'), isNull);
    });

    test('returns null for an unrecognized kind', () {
      expect(decodeNativeRecordLine('{"kind":"metric"}'), isNull);
    });

    test('returns null when a required field is missing', () {
      expect(decodeNativeRecordLine('{"kind":"span","name":"x"}'), isNull);
    });
  });
}
