import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/notifications/services/push_navigation.dart';

// A miniature of the app's router: a tab shell (dashboard/bookings), a
// top-level detail route drawn over it, and pre-shell screens.
GoRouter _router({
  required String initialLocation,
  bool shellBlocked = false,
}) =>
    GoRouter(
      initialLocation: initialLocation,
      redirect: (_, state) =>
          shellBlocked && state.matchedLocation == '/dashboard' ? '/bands' : null,
      routes: [
        GoRoute(path: '/welcome', builder: (_, __) => const Text('Welcome')),
        GoRoute(path: '/bands', builder: (_, __) => const Text('Pick a band')),
        ShellRoute(
          builder: (_, __, child) => Column(
            children: [Expanded(child: child), const Text('TAB BAR')],
          ),
          routes: [
            GoRoute(path: '/dashboard', builder: (_, __) => const Text('Dashboard')),
            GoRoute(path: '/bookings', builder: (_, __) => const Text('Bookings')),
          ],
        ),
        GoRoute(
          path: '/bookings/:bandId/:id',
          builder: (_, state) => Text('Booking ${state.pathParameters['id']}'),
        ),
      ],
    );

Future<GoRouter> _pump(WidgetTester tester, GoRouter router) async {
  addTearDown(router.dispose);
  await tester.pumpWidget(CupertinoApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('cold start: detail opens over the dashboard, Back returns to tabs',
      (tester) async {
    final router = await _pump(tester, _router(initialLocation: '/welcome'));

    await openPushRoute(router, '/bookings/1/42');
    await tester.pumpAndSettle();

    expect(find.text('Booking 42'), findsOneWidget);
    expect(router.canPop(), isTrue,
        reason: 'a plain go left the detail alone with no Back');

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('TAB BAR'), findsOneWidget);
  });

  testWidgets('app already in the shell: detail is pushed over the current tab',
      (tester) async {
    final router = await _pump(tester, _router(initialLocation: '/bookings'));

    await openPushRoute(router, '/bookings/1/42');
    await tester.pumpAndSettle();
    expect(find.text('Booking 42'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Bookings'), findsOneWidget,
        reason: 'Back returns to where the user was, not the dashboard');
  });

  testWidgets('tab destinations are reached with go, not stacked',
      (tester) async {
    final router = await _pump(tester, _router(initialLocation: '/welcome'));

    await openPushRoute(router, '/bookings');
    await tester.pumpAndSettle();

    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('TAB BAR'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  testWidgets('shell unreachable: falls back to opening the destination alone',
      (tester) async {
    final router = await _pump(
      tester,
      _router(initialLocation: '/welcome', shellBlocked: true),
    );

    final opening = openPushRoute(router, '/bookings/1/42',
        timeout: const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 150));
    await opening;
    await tester.pumpAndSettle();

    expect(find.text('Booking 42'), findsOneWidget);
  });
}
