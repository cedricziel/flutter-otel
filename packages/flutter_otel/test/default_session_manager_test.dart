import 'package:flutter/widgets.dart';
import 'package:flutter_otel/flutter_otel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Returns a `String Function()` that yields sequential, easily-asserted
/// ids ('session-0', 'session-1', ...) instead of real UUIDs.
String Function() sequentialIds() {
  var n = 0;
  return () => 'session-${n++}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DefaultSessionManager idle timeout', () {
    test(
      'keeps the same session id while activity stays within the timeout',
      () {
        var now = DateTime(2026, 1, 1, 12, 0, 0);
        final manager = DefaultSessionManager(
          idleTimeout: const Duration(minutes: 30),
          clock: () => now,
          idGenerator: sequentialIds(),
          observeLifecycle: false,
        );

        final initialId = manager.sessionId;
        now = now.add(const Duration(minutes: 10));
        manager.touch();

        expect(manager.sessionId, initialId);
      },
    );

    test('regenerates the session id once idle longer than the timeout', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final manager = DefaultSessionManager(
        idleTimeout: const Duration(minutes: 30),
        clock: () => now,
        idGenerator: sequentialIds(),
        observeLifecycle: false,
      );

      final initialId = manager.sessionId;
      now = now.add(const Duration(minutes: 31));
      manager.touch();

      expect(manager.sessionId, isNot(initialId));
    });

    test('does not regenerate exactly at the timeout boundary', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final manager = DefaultSessionManager(
        idleTimeout: const Duration(minutes: 30),
        clock: () => now,
        idGenerator: sequentialIds(),
        observeLifecycle: false,
      );

      final initialId = manager.sessionId;
      now = now.add(const Duration(minutes: 30));
      manager.touch();

      expect(manager.sessionId, initialId);
    });

    test(
      'a second regeneration only happens after another full idle period',
      () {
        var now = DateTime(2026, 1, 1, 12, 0, 0);
        final manager = DefaultSessionManager(
          idleTimeout: const Duration(minutes: 30),
          clock: () => now,
          idGenerator: sequentialIds(),
          observeLifecycle: false,
        );

        now = now.add(const Duration(minutes: 31));
        manager.touch();
        final secondId = manager.sessionId;

        now = now.add(const Duration(minutes: 10));
        manager.touch();
        expect(manager.sessionId, secondId);

        now = now.add(const Duration(minutes: 31));
        manager.touch();
        expect(manager.sessionId, isNot(secondId));
      },
    );
  });

  group('DefaultSessionManager lifecycle observation', () {
    test(
        'resuming after being backgrounded past the timeout starts a new '
        'session', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final manager = DefaultSessionManager(
        idleTimeout: const Duration(minutes: 30),
        clock: () => now,
        idGenerator: sequentialIds(),
      );
      addTearDown(manager.dispose);

      final initialId = manager.sessionId;
      now = now.add(const Duration(hours: 2));

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(manager.sessionId, isNot(initialId));
    });

    test('other lifecycle states do not touch the session', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final manager = DefaultSessionManager(
        idleTimeout: const Duration(minutes: 30),
        clock: () => now,
        idGenerator: sequentialIds(),
      );
      addTearDown(manager.dispose);

      final initialId = manager.sessionId;
      now = now.add(const Duration(hours: 2));

      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      manager.didChangeAppLifecycleState(AppLifecycleState.inactive);
      manager.didChangeAppLifecycleState(AppLifecycleState.detached);

      expect(manager.sessionId, initialId);
    });

    test('dispose can be called more than once safely', () {
      final manager = DefaultSessionManager(observeLifecycle: false);
      manager.dispose();
      expect(manager.dispose, returnsNormally);
    });
  });
}
