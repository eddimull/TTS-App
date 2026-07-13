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
    // Mirrors the explicit skip in core/config/router.dart: '/messages/new'
    // matches the '/messages' prefix but must never be persisted as a
    // restorable route — a cold-start restore into it is a dead end (no
    // bottom nav, no escape).
    if (path == '/messages/new') return;
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
        // Shell children that are NOT tab destinations — mirrors production
        // (lib/core/config/router.dart keeps these inside the ShellRoute so
        // they render with the tab bar and stay restorable).
        GoRoute(
          path: '/bookings',
          builder: (_, __) => const _Placeholder('Bookings'),
        ),
        GoRoute(
          path: '/operations',
          builder: (_, __) => const _Placeholder('Operations'),
        ),
      ],
    ),
    // Pushed over the Messages tab, outside the shell — not part of
    // AppScaffold's tabs but still matches the '/messages' prefix.
    GoRoute(
      path: '/messages/new',
      builder: (_, __) => const _Placeholder('New Message'),
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

  testWidgets(
    'navigating to /messages/new does not overwrite the saved route '
    '(regression: cold-start restore into New Message composer with no escape)',
    (tester) async {
      // Reproduces the trap at its actual trigger point: if '/messages/new'
      // is ever the persisted last-route, main.dart's restore makes it the
      // router's *initial* location on the next cold start. At that moment
      // currentConfiguration.uri.path genuinely is '/messages/new' (unlike a
      // live push on top of the shell, which leaves .uri.path at the
      // underlying shell branch). Without the explicit skip in
      // onRouteChanged, that first configuration event re-persists
      // '/messages/new', making the trap self-reinforcing with no escape.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = SpyRouteStorage(prefs);

      final router = _makeRouter('/messages/new', spy);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routeStorageProvider.overrideWithValue(AsyncValue.data(spy)),
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/messages/new',
        reason: 'Sanity check: the router really did land on the composer',
      );
      expect(
        spy.savedRoutes,
        isEmpty,
        reason: '/messages/new must never be written to RouteStorage, even '
            'as the initial cold-start location',
      );

      // Now navigate to a real shell tab: normal saving must still work,
      // proving the skip is scoped to '/messages/new' only.
      router.go('/dashboard');
      await tester.pumpAndSettle();

      expect(spy.savedRoutes.last, '/dashboard');
    },
  );
}
