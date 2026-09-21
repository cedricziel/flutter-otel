import 'package:flutter/widgets.dart';
import 'package:dart_otel_api/dart_otel_api.dart';
import 'package:uuid/uuid.dart';

/// Default [SessionManager]: generates a new session ID whenever [touch] is
/// called after more than [idleTimeout] has passed since the last activity,
/// and (optionally) registers a [WidgetsBindingObserver] so returning to the
/// foreground after a long background period starts a new session
/// automatically.
class DefaultSessionManager extends SessionManager with WidgetsBindingObserver {
  DefaultSessionManager({
    Duration idleTimeout = const Duration(minutes: 30),
    DateTime Function()? clock,
    String Function()? idGenerator,
    bool observeLifecycle = true,
  })  : _idleTimeout = idleTimeout,
        _clock = clock ?? DateTime.now,
        _idGenerator = idGenerator ?? (() => const Uuid().v4()),
        _observing = observeLifecycle {
    _sessionId = _idGenerator();
    _lastActivity = _clock();
    if (observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  final Duration _idleTimeout;
  final DateTime Function() _clock;
  final String Function() _idGenerator;
  final bool _observing;

  late String _sessionId;
  late DateTime _lastActivity;
  bool _disposed = false;

  @override
  String get sessionId => _sessionId;

  @override
  void touch() {
    final now = _clock();
    if (now.difference(_lastActivity) > _idleTimeout) {
      _sessionId = _idGenerator();
    }
    _lastActivity = now;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      touch();
    }
  }

  /// Unregisters the lifecycle observer, if one was registered. Safe to
  /// call more than once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
    }
  }
}
