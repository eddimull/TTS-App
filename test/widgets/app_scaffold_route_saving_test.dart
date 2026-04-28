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

/// Build a GoRouter that starts at [initialLocation] and wraps every shell
/// route inside [AppScaffold].
GoRouter _makeRouter(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: _shellRoutes(),
  );
}

const _shellPrefixes = ['/dashboard', '/search', '/bookings', '/library', '/more'];

/// Build a GoRouter whose redirect mirrors the production "restore last route
/// on cold start" behaviour: the restore branch is gated by a one-shot flag
/// so it can only fire on the first redirect after construction. This is
/// what `lib/core/config/router.dart` does, and the regression we want to
/// lock down is: tapping a tab must not be redirected back to the just-saved
/// route. Without the one-shot gate, mid-session writes would be echoed.
GoRouter _makeRouterWithRestore(String initialLocation, RouteStorage rs) {
  bool didConsiderRestore = false;
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) {
      if (didConsiderRestore) return null;
      didConsiderRestore = true;
      final lastRoute = rs.readLastRoute();
      final lastTs = rs.readLastRouteTimestamp();
      final isRecent =
          lastTs != null && DateTime.now().difference(lastTs).inHours < 24;
      final isShellPath = lastRoute != null &&
          _shellPrefixes.any((p) => lastRoute.startsWith(p));
      if (isRecent && isShellPath) {
        rs.clearLastRoute();
        return lastRoute;
      }
      return null;
    },
    routes: _shellRoutes(),
  );
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
          path: '/bookings',
          builder: (_, __) => const _Placeholder('Bookings'),
        ),
        GoRoute(
          path: '/search',
          builder: (_, __) => const _Placeholder('Search'),
        ),
        GoRoute(
          path: '/library',
          builder: (_, __) => const _Placeholder('Library'),
        ),
        GoRoute(
          path: '/more',
          builder: (_, __) => const _Placeholder('More'),
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
    'tapping a tab saves the current matchedLocation to RouteStorage',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = SpyRouteStorage(prefs);

      // Start on /bookings so a tap on Dashboard triggers navigation.
      final router = _makeRouter('/bookings');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Override with a pre-resolved value so .value is non-null immediately.
            routeStorageProvider.overrideWithValue(AsyncValue.data(spy)),
          ],
          child: CupertinoApp.router(
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Confirm we are on /bookings.
      expect(router.routerDelegate.currentConfiguration.last.matchedLocation,
          '/bookings');
      expect(spy.savedRoutes, isEmpty,
          reason: 'No route saved before any tab tap');

      // Tap the Dashboard tab (index 0).
      final tabBar = find.byType(CupertinoTabBar);
      expect(tabBar, findsOneWidget);

      await tester.tap(find.descendant(
        of: tabBar,
        matching: find.byIcon(CupertinoIcons.home),
      ));
      await tester.pumpAndSettle();

      // The route that was active at the time of the tap (/bookings) should
      // have been saved before navigation switched to /dashboard.
      expect(spy.savedRoutes, isNotEmpty,
          reason: 'Route must be saved when a tab is tapped');
      expect(spy.savedRoutes.last, '/bookings',
          reason: 'Saved path must be the route active at the time of the tap');
    },
  );

  testWidgets(
    'tapping a tab navigates to that tab, not back to the route just saved '
    '(regression: redirect-based restore must not consume mid-session writes)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final rs = RouteStorage(prefs);

      // Build a router whose redirect mirrors production: it restores the
      // last saved route if it's recent and a shell path. The bug: AppScaffold
      // writes the *current* route to storage before calling context.go(),
      // so the redirect then "restores" that just-written route — sending the
      // user back where they started. This test asserts that does NOT happen.
      final router = _makeRouterWithRestore('/dashboard', rs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routeStorageProvider.overrideWithValue(AsyncValue.data(rs)),
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // We start on /dashboard. No route has been saved yet, so the redirect
      // should not redirect anywhere.
      expect(router.routerDelegate.currentConfiguration.last.matchedLocation,
          '/dashboard');
      expect(rs.readLastRoute(), isNull,
          reason: 'No route should be persisted at startup');

      // Tap the Bookings tab.
      final tabBar = find.byType(CupertinoTabBar);
      await tester.tap(find.descendant(
        of: tabBar,
        matching: find.byIcon(CupertinoIcons.book),
      ));
      await tester.pumpAndSettle();

      // The user MUST land on /bookings. With the bug, they get bounced back
      // to /dashboard because the redirect reads the just-saved /dashboard
      // route and returns it.
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/bookings',
        reason: 'Tapping the Bookings tab must navigate to /bookings, not be '
            'redirected back to the route that was just persisted',
      );
      // Body of the Bookings page is rendered (the placeholder text appears
      // both as the tab label and as the page body — both are fine).
      expect(find.text('Bookings'), findsWidgets);
    },
  );

  testWidgets(
    'each remaining tab (Search, Library, More) is reachable from /dashboard '
    'without being bounced by the restore redirect',
    (tester) async {
      // This locks down the user-reported symptom: "search, bookings, library,
      // more are all unavailable" from the dashboard.
      final cases = <(IconData, String, String)>[
        (CupertinoIcons.search, '/search', 'Search'),
        (CupertinoIcons.book, '/bookings', 'Bookings'),
        (CupertinoIcons.music_note_list, '/library', 'Library'),
        (CupertinoIcons.ellipsis, '/more', 'More'),
      ];

      for (final (icon, expectedPath, label) in cases) {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final rs = RouteStorage(prefs);
        final router = _makeRouterWithRestore('/dashboard', rs);

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
