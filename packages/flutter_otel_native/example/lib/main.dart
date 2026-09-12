import 'package:flutter/material.dart';
import 'package:flutter_otel_api/flutter_otel_api.dart';
import 'package:flutter_otel_native/flutter_otel_native.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _bridge = NativeTelemetryBridge();
  String _status = 'Draining native queue...';

  @override
  void initState() {
    super.initState();
    _drain();
  }

  Future<void> _drain() async {
    final result = await _bridge.drainAndForward(
      tracerProvider: _CountingTracerProvider(),
      loggerProvider: _CountingLoggerProvider(),
    );
    if (!mounted) return;
    setState(() {
      _status = 'ingested: ${result.recordsIngested}, '
          'skipped: ${result.recordsSkipped}, '
          'dropped: ${result.recordsDropped}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_otel_native example')),
        body: Center(child: Text(_status)),
      ),
    );
  }
}

class _CountingTracerProvider implements TracerProvider {
  @override
  void ingestSpan(SpanData span) {}

  @override
  Tracer getTracer({String name = 'flutter_otel', String? version}) =>
      const NoopTracer('example');

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

class _CountingLoggerProvider implements LoggerProvider {
  @override
  void ingestLogRecord(LogRecord record) {}

  @override
  Logger getLogger({String name = 'flutter_otel', String? version}) =>
      throw UnimplementedError('not exercised by this example');

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
