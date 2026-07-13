import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/storage/hint_storage.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/dashboard/screens/dashboard_screen.dart';

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override
  Future<AuthState> build() async => _fixed;
}

class _FixedDashboardNotifier extends DashboardNotifier {
  _FixedDashboardNotifier(this._state);
  final DashboardState _state;
  @override
  Future<DashboardState> build() async => _state;
  @override
  Future<void> refresh() async {}
}

void main() {
  const bandA = BandSummary(id: 1, name: 'Alpha', isOwner: true);

  Widget host({
    required SharedPreferences prefs,
  }) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            return const CupertinoPageScaffold(
              child: DashboardScreen(),
            );
          },
        ),
        GoRoute(
          path: '/operations',
          builder: (context, state) {
            return const CupertinoPageScaffold(
              child: Center(child: Text('Operations Stub')),
            );
          },
        ),
        GoRoute(
          path: '/account',
          builder: (context, state) {
            return const CupertinoPageScaffold(
              child: Center(child: Text('Account Stub')),
            );
          },
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(
              const AuthAuthenticated(
                user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
                bands: [bandA],
              ),
            )),
        dashboardProvider.overrideWith(() => _FixedDashboardNotifier(
              DashboardState(events: const [], upcomingCharts: const [], loadedFrom: DateTime(2026)),
            )),
        hintStorageProvider.overrideWithValue(
          AsyncValue<HintStorage>.data(HintStorage(prefs)),
        ),
      ],
      child: CupertinoApp.router(
        routerConfig: router,
      ),
    );
  }

  testWidgets('hamburger button opens Operations', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(host(
      prefs: prefs,
    ));
    await tester.pumpAndSettle();

    // Find and tap the hamburger (Operations menu) button
    // We find it by looking for the leading button in the nav bar (the hamburger icon)
    final hamburgerIcon = find.byIcon(CupertinoIcons.line_horizontal_3);
    expect(hamburgerIcon, findsOneWidget);

    await tester.tap(hamburgerIcon);
    await tester.pumpAndSettle();

    // Verify we navigated to /operations by checking for the stub screen text
    expect(find.text('Operations Stub'), findsOneWidget);
  });

  testWidgets('hint is visible when not dismissed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(host(
      prefs: prefs,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bookings has moved'), findsOneWidget);
  });

  testWidgets('tapping close button dismisses hint and persists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(host(
      prefs: prefs,
    ));
    await tester.pumpAndSettle();

    // Verify hint is visible
    expect(find.textContaining('Bookings has moved'), findsOneWidget);

    // Tap the close button (xmark icon)
    final closeButton = find.byIcon(CupertinoIcons.xmark);
    expect(closeButton, findsOneWidget);

    await tester.tap(closeButton);
    await tester.pumpAndSettle();

    // Hint should be gone
    expect(find.textContaining('Bookings has moved'), findsNothing);

    // Rebuild with a fresh provider scope but same prefs instance
    // to verify the dismissal was persisted
    await tester.pumpWidget(host(
      prefs: prefs,
    ));
    await tester.pumpAndSettle();

    // Hint should still be gone
    expect(find.textContaining('Bookings has moved'), findsNothing);
  });
}
