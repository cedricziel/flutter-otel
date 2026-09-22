import 'app_event_logger.dart';

/// One entry recorded by a [BreadcrumbTrail]: an app event and when it
/// happened.
class Breadcrumb {
  const Breadcrumb(this.name, this.attributes, this.timestamp);

  final String name;
  final Map<String, Object> attributes;
  final DateTime timestamp;

  @override
  String toString() {
    final attrs = attributes.isEmpty ? '' : ' $attributes';
    return '${timestamp.toIso8601String()} $name$attrs';
  }
}

/// Keeps the last [capacity] app events in memory, so a crash reported soon
/// after can be logged together with the trail of events that led to it —
/// the way breadcrumbs work in a crash reporter.
///
/// [asAppEventLogger] wraps an existing [AppEventLogger] so recording a
/// breadcrumb is a drop-in replacement for the app's existing event
/// logging, not a second call site to remember.
class BreadcrumbTrail {
  BreadcrumbTrail({this.capacity = 20});

  final int capacity;
  final _entries = <Breadcrumb>[];

  void record(String name, [Map<String, Object> attributes = const {}]) {
    _entries.add(Breadcrumb(name, attributes, DateTime.now().toUtc()));
    if (_entries.length > capacity) _entries.removeAt(0);
  }

  /// The recorded breadcrumbs, oldest first.
  List<Breadcrumb> get recent => List.unmodifiable(_entries);

  /// Returns an [AppEventLogger] that records each event here, then
  /// forwards it to [logger] unchanged.
  AppEventLogger asAppEventLogger(AppEventLogger logger) =>
      (name, [attributes = const {}]) {
        record(name, attributes);
        logger(name, attributes);
      };
}
