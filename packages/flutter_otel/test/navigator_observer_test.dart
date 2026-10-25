import 'package:flutter/widgets.dart';
import 'package:flutter_otel/flutter_otel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_logger.dart';

Route<void> route(String? name, {Object? arguments}) => PageRouteBuilder<void>(
  settings: RouteSettings(name: name, arguments: arguments),
  pageBuilder: (_, __, ___) => const SizedBox(),
);

void main() {
  late RecordingLogger logger;
  late BreadcrumbTrail trail;

  OTelNavigatorObserver build({
    RouteNameExtractor? extractor,
    UnnamedRoutePolicy policy = UnnamedRoutePolicy.placeholder,
  }) => OTelNavigatorObserver(
    logEvent: appEventLogger(logger),
    breadcrumbs: trail,
    routeNameExtractor: extractor,
    unnamedRoutePolicy: policy,
  );

  setUp(() {
    logger = RecordingLogger();
    trail = BreadcrumbTrail();
  });

  test('push records a log event and a breadcrumb', () {
    build().didPush(route('/b'), route('/a'));

    final record = logger.records.single;
    expect(record.body, 'app.navigation');
    expect(record.attributes, {
      'navigation.action': 'push',
      'screen.name': '/b',
      'previous_screen.name': '/a',
    });
    expect(trail.recent.single.name, 'app.navigation');
    expect(trail.recent.single.attributes, record.attributes);
  });

  test('pop reports the revealed screen and the one left', () {
    build().didPop(route('/b'), route('/a'));

    expect(logger.records.single.attributes, {
      'navigation.action': 'pop',
      'screen.name': '/a',
      'previous_screen.name': '/b',
    });
  });

  test('pop of the root route has no screen.name', () {
    build().didPop(route('/a'), null);

    expect(logger.records.single.attributes, {
      'navigation.action': 'pop',
      'previous_screen.name': '/a',
    });
  });

  test('replace reports the new and old screens', () {
    build().didReplace(newRoute: route('/b'), oldRoute: route('/a'));

    expect(logger.records.single.attributes, {
      'navigation.action': 'replace',
      'screen.name': '/b',
      'previous_screen.name': '/a',
    });
  });

  test('remove reports only the removed screen', () {
    build().didRemove(route('/a'), route('/z'));

    expect(logger.records.single.attributes, {
      'navigation.action': 'remove',
      'previous_screen.name': '/a',
    });
  });

  test('never records route arguments', () {
    build().didPush(route('/b', arguments: 'secret'), null);

    expect(logger.records.single.attributes.values, isNot(contains('secret')));
  });

  test('the extractor normalises names', () {
    final observer = build(
      extractor: (r) =>
          r.settings.name?.replaceAll(RegExp(r'/[0-9a-f-]{36}'), '/:id'),
    );

    observer.didPush(
      route('/servers/3f2a1c4e-0000-4000-8000-123456789abc'),
      route('/servers'),
    );

    expect(logger.records.single.attributes['screen.name'], '/servers/:id');
  });

  test('unnamed routes use the placeholder by default', () {
    build().didPush(route(null), route('/a'));

    expect(logger.records.single.attributes['screen.name'], 'unnamed');
  });

  test('unnamed routes can be skipped', () {
    build(policy: UnnamedRoutePolicy.skip).didPush(route(null), route('/a'));

    expect(logger.records, isEmpty);
    expect(trail.recent, isEmpty);
  });

  test('defaults record nothing visible and never throw', () {
    expect(
      () => OTelNavigatorObserver().didPush(route('/a'), null),
      returnsNormally,
    );
  });

  test('a throwing extractor does not escape', () {
    final observer = build(extractor: (_) => throw StateError('boom'));

    expect(() => observer.didPush(route('/a'), null), returnsNormally);
  });

  testWidgets('observes a real Navigator', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        navigatorKey: key,
        navigatorObservers: [build()],
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (c, _, __) => builder(c),
        ),
        routes: {
          '/': (_) => const SizedBox(),
          '/next': (_) => const SizedBox(),
        },
      ),
    );
    key.currentState!.pushNamed('/next');
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pumpAndSettle();

    final actions = logger.records
        .map((r) => r.attributes['navigation.action'])
        .toList();
    expect(actions, ['push', 'push', 'pop']);
  });
}
