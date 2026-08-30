import 'package:flutter_otel_api/flutter_otel_api.dart';

/// Concrete [LoggerProvider] backed by a single [LogRecordProcessor].
///
/// Every [Logger] vended by this provider automatically stamps
/// `traceId`/`spanId` from [Span.current] onto each [LogRecord] it emits,
/// whenever a span is active and neither ID was already set explicitly —
/// this is the trace-to-log correlation mechanism. When [sessionManager] is
/// also non-null, a `session.id` attribute (read from
/// [SessionManager.sessionId]) is merged in too, and
/// [SessionManager.touch] is called on every emit.
class SdkLoggerProvider implements LoggerProvider {
  SdkLoggerProvider({
    required this.resource,
    required this.processor,
    this.sessionManager,
  });

  final OTelResource resource;
  final LogRecordProcessor processor;
  final SessionManager? sessionManager;

  final Map<(String, String?), Logger> _loggers = {};

  @override
  Logger getLogger({String name = 'flutter_otel', String? version}) {
    final key = (name, version);
    return _loggers.putIfAbsent(
      key,
      () => _SdkLogger(
        processor: processor,
        sessionManager: sessionManager,
        scopeName: name,
        scopeVersion: version,
      ),
    );
  }

  @override
  Future<void> forceFlush() => processor.forceFlush();

  @override
  Future<void> shutdown() => processor.shutdown();
}

class _SdkLogger extends Logger {
  _SdkLogger({
    required this.processor,
    required this.sessionManager,
    required this.scopeName,
    required this.scopeVersion,
  });

  final LogRecordProcessor processor;
  final SessionManager? sessionManager;
  final String scopeName;
  final String? scopeVersion;

  @override
  void emit(LogRecord record) {
    var toEmit = record.withScope(scopeName, scopeVersion);
    final span = Span.current;
    if (span != null && span.spanContext.isValid) {
      toEmit = toEmit.withTraceCorrelation(
        span.spanContext.traceId,
        span.spanContext.spanId,
      );
    }
    final manager = sessionManager;
    if (manager != null) {
      manager.touch();
      toEmit = toEmit.withAttributes({'session.id': manager.sessionId});
    }
    processor.onEmit(toEmit);
  }
}
