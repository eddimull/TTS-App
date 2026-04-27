import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';
import 'package:tts_bandmate/shared/widgets/app_scaffold.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
// connectivity_plus not needed;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RouteStorage routeStorage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    routeStorage = RouteStorage(prefs);
  });

  Widget buildTestApp({required String initialLocation}) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppScaffold(child: child),
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (_, __) => const CupertinoPageScaffold(child: Text('Dashboard')),
            ),
            GoRoute(
              path: '/library',
              builder: (_, __) => const CupertinoPageScaffold(child: Text('Library')),
            ),
            GoRoute(
              path: '/bookings',
              builder: (_, __) => const CupertinoPageScaffold(child: Text('Bookings')),
            ),
            GoRoute(
              path: '/search',
              builder: (_, __) => const CupertinoPageScaffold(child: Text('Search')),
            ),
            GoRoute(
              path: '/more',
              builder: (_, __) => const CupertinoPageScaffold(child: Text('More')),
            ),
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        routeStorageProvider.overrideWith((_) async => routeStorage),
        connectivityProvider.overrideWith(
          (_) => Stream.value(true),
        ),
      ],
      child: CupertinoApp.router(routerConfig: router),
    );
  }

  testWidgets('AppScaffold saves tab root path on build', (tester) async {
    await tester.pumpWidget(buildTestApp(initialLocation: '/library'));
    await tester.pumpAndSettle();

    // Should have saved /library (the tab root)
    expect(routeStorage.readLastRoute(), '/library');
  });

  testWidgets('AppScaffold saves updated tab after navigation', (tester) async {
    await tester.pumpWidget(buildTestApp(initialLocation: '/dashboard'));
    await tester.pumpAndSettle();
    expect(routeStorage.readLastRoute(), '/dashboard');

    // Tap the Library tab
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(routeStorage.readLastRoute(), '/library');
  });

  testWidgets('navigating does not produce extra builds or nav events', (tester) async {
    int libraryBuildCount = 0;

    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppScaffold(child: child),
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (_, __) => const CupertinoPageScaffold(child: Text('Dashboard')),
            ),
            GoRoute(
              path: '/library',
              builder: (_, __) {
                libraryBuildCount++;
                return const CupertinoPageScaffold(child: Text('Library'));
              },
            ),
            GoRoute(path: '/bookings', builder: (_, __) => const CupertinoPageScaffold(child: Text('Bookings'))),
            GoRoute(path: '/search', builder: (_, __) => const CupertinoPageScaffold(child: Text('Search'))),
            GoRoute(path: '/more', builder: (_, __) => const CupertinoPageScaffold(child: Text('More'))),
          ],
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        routeStorageProvider.overrideWith((_) async => routeStorage),
        connectivityProvider.overrideWith(
          (_) => Stream.value(true),
        ),
      ],
      child: CupertinoApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    // Library screen should build a small number of times (1-2 is normal for
    // Flutter's build optimisation), but NOT many times due to redirect loops.
    expect(libraryBuildCount, lessThan(5),
        reason: 'Library should not be rebuilt many times — indicates redirect loop');
    expect(find.text('Library'), findsWidgets);
  });
}
