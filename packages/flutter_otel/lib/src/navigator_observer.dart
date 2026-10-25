import 'package:flutter/widgets.dart';

import 'app_event_logger.dart';
import 'breadcrumb_trail.dart';
import 'safely.dart';

/// Event name used for every navigation record and breadcrumb.
const navigationEventName = 'app.navigation';

/// Turns a [Route] into the screen name that gets recorded, or `null` when it
/// has none worth recording.
///
/// Use it to collapse parameterised paths into templates, for example
/// `/servers/3f2a…` into `/servers/:id`.
typedef RouteNameExtractor = String? Function(Route<dynamic> route);

/// What to do with a route whose [RouteNameExtractor] returned `null` or an
/// empty name.
enum UnnamedRoutePolicy {
  /// Record the route under [OTelNavigatorObserver.unnamedPlaceholder].
  placeholder,

  /// Leave the route out: no log record and no breadcrumb for events about it.
  skip,
}

/// Records navigation as `app.navigation` events, both as a log record and as
/// a breadcrumb, so a crash report shows the screens that led to it.
///
/// Attributes: `navigation.action` (`push`, `pop`, `replace` or `remove`),
/// `screen.name` (the screen now in front) and `previous_screen.name` (the
/// screen that was left). For `remove`, only `previous_screen.name` is set.
///
/// Only the route name is read; [RouteSettings.arguments] never are. Works
/// with go_router through `GoRouter(observers: [...])`.
///
/// Recording never throws and does nothing when [logEvent] is
/// [noopAppEventLogger] and no [breadcrumbs] are given.
class OTelNavigatorObserver extends NavigatorObserver {
  OTelNavigatorObserver({
    AppEventLogger logEvent = noopAppEventLogger,
    this.breadcrumbs,
    RouteNameExtractor? routeNameExtractor,
    this.unnamedRoutePolicy = UnnamedRoutePolicy.placeholder,
    this.unnamedPlaceholder = 'unnamed',
  }) : _logEvent = logEvent,
       _extractName = routeNameExtractor ?? _settingsName;

  final AppEventLogger _logEvent;
  final BreadcrumbTrail? breadcrumbs;
  final UnnamedRoutePolicy unnamedRoutePolicy;
  final String unnamedPlaceholder;
  final RouteNameExtractor _extractName;

  static String? _settingsName(Route<dynamic> route) => route.settings.name;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('push', to: route, from: previousRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('pop', to: previousRoute, from: route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record('replace', to: newRoute, from: oldRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('remove', from: route);

  void _record(String action, {Route<dynamic>? to, Route<dynamic>? from}) {
    safely(() {
      final toName = _resolve(to);
      final fromName = _resolve(from);
      final primary = to != null ? toName : fromName;
      if (primary == null) return;

      final attributes = <String, Object>{
        'navigation.action': action,
        if (toName != null) 'screen.name': toName,
        if (fromName != null) 'previous_screen.name': fromName,
      };
      breadcrumbs?.record(navigationEventName, attributes);
      _logEvent(navigationEventName, attributes);
    });
  }

  /// The name to record for [route], or `null` when it is absent or skipped.
  String? _resolve(Route<dynamic>? route) {
    if (route == null) return null;
    final name = _extractName(route);
    if (name != null && name.isNotEmpty) return name;
    return unnamedRoutePolicy == UnnamedRoutePolicy.placeholder
        ? unnamedPlaceholder
        : null;
  }
}
