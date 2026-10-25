import 'package:flutter_otel/flutter_otel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps recorded breadcrumbs in order', () {
    final trail = BreadcrumbTrail();

    trail.record('auth.state', {'state': 'ready'});
    trail.record('session.created');

    expect(trail.recent.map((b) => b.name), ['auth.state', 'session.created']);
    expect(trail.recent.first.attributes, {'state': 'ready'});
  });

  test('drops the oldest entry once past capacity', () {
    final trail = BreadcrumbTrail(capacity: 2);

    trail.record('one');
    trail.record('two');
    trail.record('three');

    expect(trail.recent.map((b) => b.name), ['two', 'three']);
  });

  test('asAppEventLogger records here and still forwards to the wrapped logger',
      () {
    final trail = BreadcrumbTrail();
    final forwarded = <String>[];

    trail.asAppEventLogger((name, [attributes = const {}]) {
      forwarded.add(name);
    })('auth.state', {'state': 'ready'});

    expect(forwarded, ['auth.state']);
    expect(trail.recent.single.name, 'auth.state');
    expect(trail.recent.single.attributes, {'state': 'ready'});
  });

  test('toString renders a compact single line', () {
    final breadcrumb = Breadcrumb(
      'auth.state',
      {'state': 'ready'},
      DateTime.utc(2026, 1, 2, 3, 4, 5),
    );

    expect(
      breadcrumb.toString(),
      '2026-01-02T03:04:05.000Z auth.state {state: ready}',
    );
  });
}
