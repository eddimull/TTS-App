import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/dashboard/providers/calendar_filter_provider.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/dashboard/screens/dashboard_screen.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

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
  const bandB = BandSummary(id: 2, name: 'Bravo', isOwner: false);

  EventSummary evt({
    required String key,
    required String date,
    required BandSummary band,
    String source = 'booking',
    String? status = 'confirmed',
  }) =>
      EventSummary(
        key: key,
        title: '$key title',
        date: date,
        eventSource: source,
        status: status,
        band: band,
      );

  Widget host({required List<EventSummary> events}) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(
              const AuthAuthenticated(
                user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
                bands: [bandA, bandB],
              ),
            )),
        dashboardProvider.overrideWith(() => _FixedDashboardNotifier(
              DashboardState(events: events, upcomingCharts: const []),
            )),
      ],
      child: const CupertinoApp(home: Material(child: DashboardScreen())),
    );
  }

  testWidgets('hiding a band hides its event from the events list',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final events = [
      evt(key: 'a', date: '2026-05-10', band: bandA),
      evt(key: 'b', date: '2026-05-11', band: bandB),
    ];

    await tester.pumpWidget(host(events: events));
    await tester.pumpAndSettle();

    expect(find.text('a title'), findsOneWidget);
    expect(find.text('b title'), findsOneWidget);

    // Hide band B by mutating the provider directly (faster than driving the
    // sheet UI here — the sheet is covered by its own widget test).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardScreen)),
    );
    container.read(calendarFilterProvider.notifier).toggleBand(2);
    await tester.pumpAndSettle();

    expect(find.text('a title'), findsOneWidget);
    expect(find.text('b title'), findsNothing);
  });

  testWidgets('filter-aware empty state shows Clear filters button',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final events = [evt(key: 'a', date: '2026-05-10', band: bandA)];

    await tester.pumpWidget(host(events: events));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardScreen)),
    );
    container.read(calendarFilterProvider.notifier).toggleBand(1);
    await tester.pumpAndSettle();

    expect(find.text('No events match your filters'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();

    expect(container.read(calendarFilterProvider).isActive, false);
    expect(find.text('a title'), findsOneWidget);
  });
}
