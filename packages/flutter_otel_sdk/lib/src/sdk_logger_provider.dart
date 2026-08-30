import 'package:flutter_otel_api/flutter_otel_api.dart';

/// Concrete [LoggerProvider] backed by a single [LogRecordProcessor].
///
/// When [sessionManager] is non-null, every [Logger] vended by this
/// provider automatically merges a `session.id` attribute (read from
/// [SessionManager.sessionId]) onto each [LogRecord] it emits, and calls
/// [SessionManager.touch] on every emit.
class SdkLoggerProvider implements LoggerProvider {
  SdkLoggerProvider({
    required this.resource,
    required this.processor,
    this.sessionManager,
  });

  final OTelResource resource;
  final LogRecordProcessor processor;
  final SessionManager? sessionManager;

  final Map<String, Logger> _loggers = {};

  @override
  Logger getLogger({String name = 'flutter_otel', String? version}) {
    final key = '$name@${version ?? ''}';
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
    final manager = sessionManager;
    if (manager != null) {
      manager.touch();
      toEmit = toEmit.withAttributes({'session.id': manager.sessionId});
    }
    processor.onEmit(toEmit);
  }
}
