/// Tracks a rolling "session" identifier for the current app run, so log
/// (and later, trace/metric) records can be correlated by user session.
///
/// This interface is platform-agnostic; [flutter_otel_sdk] provides a
/// default implementation that also hooks Flutter's app lifecycle.
abstract class SessionManager {
  /// The current session's identifier.
  String get sessionId;

  /// Records activity. Implementations should regenerate [sessionId] if
  /// this is called after the configured idle timeout has elapsed since
  /// the previous activity.
  void touch();
}
