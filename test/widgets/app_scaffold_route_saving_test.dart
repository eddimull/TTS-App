import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';
import 'package:tts_bandmate/shared/widgets/app_scaffold.dart';

// ── Spy RouteStorage ───────────────────────────────────────────────────────────

class SpyRouteStorage extends RouteStorage {
  SpyRouteStorage(super.prefs);

  final List<String> savedRoutes = [];

  @override
  void writeLastRoute(String path) {
    savedRoutes.add(path);
    super.writeLastRoute(path);
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

const _shellPrefixes = ['/dashboard', '/search', '/messages', '/library', '/settings'];

/// Build a GoRouter that mirrors production: the only side-effect on
/// navigation is a `routerDelegate` listener that persists the active shell
/// route to [RouteStorage]. There is no save logic in the redirect callback
/// and none in the tab tap handler — that's the bug we're locking out.
GoRouter _makeRouter(String initialLocation, RouteStorage rs) {
  late final GoRouter router;
  router = GoRouter(
    initialLocation: initialLocation,
    routes: _shellRoutes(),
  );

  void onRouteChanged() {
    final path = router.routerDelegate.currentConfiguration.uri.path;
    if (!_shellPrefixes.any((p) => path.startsWith(p))) return;
    rs.writeLastRoute(path);
  }

  router.routerDelegate.addListener(onRouteChanged);
  addTearDown(() => router.routerDelegate.removeListener(onRouteChanged));
  return router;
}

List<RouteBase> _shellRoutes() {
  return [
    ShellRoute(
      builder: (context, state, child) => AppScaffold(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const _Placeholder('Dashboard'),
        ),
        GoRoute(
          path: '/search',
          builder: (_, __) => const _Placeholder('Search'),
        ),
        GoRoute(
          path: '/messages',
          builder: (_, __) => const _Placeholder('Messages'),
        ),
        GoRoute(
          path: '/library',
          builder: (_, __) => const _Placeholder('Library'),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const _Placeholder('Settings'),
        ),
      ],
    ),
  ];
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Center(child: Text(label));
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'navigating to a shell route saves that destination to RouteStorage',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = SpyRouteStorage(prefs);

      // Start on /messages so the initial navigation is captured.
      final router = _makeRouter('/messages', spy);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routeStorageProvider.overrideWithValue(AsyncValue.data(spy)),
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(spy.savedRoutes.last, '/messages',
          reason: 'Initial shell location must be persisted');

      // Tap the Dashboard tab.
      final tabBar = find.byType(CupertinoTabBar);
      await tester.tap(find.descendant(
        of: tabBar,
        matching: find.byIcon(CupertinoIcons.home),
      ));
      await tester.pumpAndSettle();

      expect(spy.savedRoutes.last, '/dashboard',
          reason: 'Saved path must be the destination, not the departing route');
    },
  );

  testWidgets(
    'tapping a tab navigates to that tab — no bounce-back from a save side-effect '
    '(regression: writes must not be echoed as redirects)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final rs = RouteStorage(prefs);

      final router = _makeRouter('/dashboard', rs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routeStorageProvider.overrideWithValue(AsyncValue.data(rs)),
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.last.matchedLocation,
          '/dashboard');

      // Tap the Messages tab.
      final tabBar = find.byType(CupertinoTabBar);
      await tester.tap(find.descendant(
        of: tabBar,
        matching: find.byIcon(CupertinoIcons.chat_bubble_2),
      ));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/messages',
        reason: 'Tapping Messages must navigate to /messages on the FIRST tap',
      );
    },
  );

  testWidgets(
    'every shell tab is reachable from /dashboard with a single tap',
    (tester) async {
      // Locks down the user-reported symptom: tabs were unreachable on first
      // tap because the redirect was bouncing back to the just-saved route.
      final cases = <(IconData, String, String)>[
        (CupertinoIcons.search, '/search', 'Search'),
        (CupertinoIcons.chat_bubble_2, '/messages', 'Messages'),
        (CupertinoIcons.music_note_list, '/library', 'Library'),
        (CupertinoIcons.ellipsis, '/settings', 'Settings'),
      ];

      for (final (icon, expectedPath, label) in cases) {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final rs = RouteStorage(prefs);
        final router = _makeRouter('/dashboard', rs);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              routeStorageProvider.overrideWithValue(AsyncValue.data(rs)),
            ],
            child: CupertinoApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        final tabBar = find.byType(CupertinoTabBar);
        await tester.tap(find.descendant(
          of: tabBar,
          matching: find.byIcon(icon),
        ));
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.last.matchedLocation,
          expectedPath,
          reason: 'Tapping $label must reach $expectedPath',
        );
      }
    },
  );
}
