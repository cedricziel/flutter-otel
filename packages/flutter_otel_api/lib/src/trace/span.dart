import 'dart:async';

import 'span_context.dart';
import 'status_code.dart';

/// A single unit of work with a start and end time, contributing to a
/// distributed trace.
///
/// Concrete instances are created by a `Tracer` (via `startSpan` or
/// `startActiveSpan`) — application code never implements this directly.
abstract class Span {
  /// This span's trace/span IDs.
  SpanContext get spanContext;

  /// This span's name.
  String get name;

  /// Whether this span is still open (i.e. [end] has not been called).
  /// A non-recording span (e.g. [end] already called, or a no-op
  /// implementation) silently ignores further mutation.
  bool get isRecording;

  /// Sets a single attribute. A no-op once the span has ended.
  void setAttribute(String key, Object? value);

  /// Merges [attributes] onto this span's attribute set. A no-op once the
  /// span has ended.
  void setAttributes(Map<String, Object?> attributes);

  /// Records a timestamped event on this span. A no-op once the span has
  /// ended.
  void addEvent(
    String name, {
    Map<String, Object?>? attributes,
    DateTime? timestamp,
  });

  /// Sets the span's final status. A no-op once the span has ended.
  void setStatus(StatusCode code, {String? description});

  /// Records [exception] (and optionally [stackTrace]) as an `exception`
  /// event, following the OTel exception semantic conventions. Does not by
  /// itself change [setStatus] — callers that want an error status still
  /// call [setStatus] explicitly (this is what `Tracer.startActiveSpan`
  /// does when `body` throws).
  void recordException(
    Object exception, {
    StackTrace? stackTrace,
    Map<String, Object?>? attributes,
  });

  /// Ends the span, snapshotting it for export. Calling this more than once
  /// is a safe no-op — only the first call has any effect.
  void end([DateTime? endTime]);

  static final Object _zoneKey = Object();

  /// The span active in the current async [Zone], or `null` if none is.
  /// Set implicitly by `Tracer.startActiveSpan` (via [runWithSpan]) for the
  /// duration of the active operation, which is what makes trace-to-log
  /// correlation automatic without every call site threading a span
  /// through manually.
  static Span? get current => Zone.current[_zoneKey] as Span?;

  /// Runs [body] with [span] as [current] for its duration, including
  /// across `await` gaps (Dart zones are "sticky": an async function keeps
  /// running in the zone that was active when it started).
  ///
  /// This is the mechanism `Tracer` SDK implementations use to back
  /// `startActiveSpan`; application code should call `startActiveSpan`
  /// instead of this directly.
  static Future<T> runWithSpan<T>(Span span, Future<T> Function() body) =>
      runZoned(body, zoneValues: {_zoneKey: span});
}
