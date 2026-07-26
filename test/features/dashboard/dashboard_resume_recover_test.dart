// Regression test for the app-resume dashboard bug: a provider reset (app
// resume, realtime signal, pull-to-refresh) replaces the dashboard's loaded
// window with the initial one while the calendar's _focusedDay stays parked
// on whatever month the user swiped to — leaving that month's events blank
// until a manual page-change re-fires ensureMonthLoaded. The fix wires a
// ref.listen in DashboardScreen that re-covers the focused month whenever the
// provider state changes and no longer covers it.
//
// This test drives the REAL TableCalendar (via its next-month chevron,
// following the pattern in test/widgets/dashboard_calendar_filter_integration_test.dart)
// so the reproduction is end-to-end: real widget, real DashboardNotifier,
// fake repository only at the network boundary.

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons, Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';
import 'package:tts_bandmate/features/dashboard/data/models/upcoming_chart.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/dashboard/screens/dashboard_screen.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

final _throwingDio = Dio();

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override
  Future<AuthState> build() async => _fixed;
}

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

/// Fake repository: records every loadNewerEvents window requested and
/// always returns one scripted event per call so state visibly changes.
class _FakeDashboardRepository extends DashboardRepository {
  _FakeDashboardRepository() : super(_throwingDio);

  final List<(String, String)> requestedNewerWindows = [];
  int _newerCallCount = 0;
  int getDashboardCallCount = 0;

  @override
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard({String? to}) async {
    getDashboardCallCount++;
    return (events: const <EventSummary>[], upcomingCharts: const <UpcomingChart>[]);
  }

  @override
  Future<List<EventSummary>> loadOlderEvents(String beforeDate) async =>
      const [];

  @override
  Future<List<EventSummary>> loadNewerEvents(
      String afterDate, String beforeDate) async {
    requestedNewerWindows.add((afterDate, beforeDate));
    _newerCallCount++;
    return [
      EventSummary.fromJson({
        'id': 1000 + _newerCallCount,
        'key': 'resume-recover-$_newerCallCount',
        'title': 'Resume Recover Event $_newerCallCount',
        'date': beforeDate, // lands just inside the fetched window
        'event_source': 'booking',
      }),
    ];
  }
}

void main() {
  const band = BandSummary(id: 1, name: 'Alpha', isOwner: true);

  Widget host(_FakeDashboardRepository repo) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(
              const AuthAuthenticated(
                user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
                bands: [band],
              ),
            )),
        selectedBandProvider.overrideWith(() => _StubBand()),
        dashboardRepositoryProvider.overrideWithValue(repo),
      ],
      child: const CupertinoApp(home: Material(child: DashboardScreen())),
    );
  }

  testWidgets(
      'a provider reset while parked on a future month re-fetches that month '
      'without requiring another page change', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _FakeDashboardRepository();
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardScreen)),
    );

    // Initial loadedTo watermark before any navigation.
    final initialLoadedTo =
        container.read(dashboardProvider).value!.loadedTo;

    // Advance the calendar's focused month past the loaded window by tapping
    // the TableCalendar header's next-month chevron. Each tap fires
    // onPageChanged -> ensureMonthLoaded, which the fake repo fulfills.
    final nextChevron = find.byIcon(Icons.chevron_right);
    expect(nextChevron, findsOneWidget);

    // 90-day initial forward window is roughly 3 months; go 4 to be safely
    // beyond it regardless of which day-of-month "today" is.
    for (var i = 0; i < 4; i++) {
      await tester.tap(nextChevron);
      await tester.pumpAndSettle();
    }

    final afterNavState = container.read(dashboardProvider).value!;
    final focusedMonthAfterNav = afterNavState.loadedTo;
    expect(focusedMonthAfterNav.isAfter(initialLoadedTo), isTrue,
        reason: 'navigating forward 4 months must have advanced the '
            'loadedTo watermark past its initial value');
    final callsAfterNav = repo.requestedNewerWindows.length;
    expect(callsAfterNav, greaterThan(0),
        reason: 'paging forward must have triggered at least one '
            'loadNewerEvents call');

    // Simulate the app-resume blanket invalidation: the provider rebuilds
    // via build(), which resets loadedFrom/loadedTo to the initial window —
    // but the calendar's _focusedDay widget state survives untouched.
    final getDashboardCallsBeforeReset = repo.getDashboardCallCount;
    container.invalidate(dashboardProvider);
    await tester.pumpAndSettle();

    // Sanity check that invalidate() actually reproduced the bug precondition
    // (a fresh build() -> getDashboard() call replacing the loaded window) —
    // checked via call count rather than the final loadedTo value, since the
    // fix's re-fetch can converge loadedTo back to the same value by the time
    // pumpAndSettle returns.
    expect(repo.getDashboardCallCount, greaterThan(getDashboardCallsBeforeReset),
        reason: 'invalidate() must have re-run build(), issuing a fresh '
            'getDashboard() call that resets the loaded window');

    // The fix: without any further page change, a NEW loadNewerEvents call
    // must have fired to re-cover the still-focused (now out-of-window)
    // month, and the resulting state's events must include that new batch.
    expect(repo.requestedNewerWindows.length, greaterThan(callsAfterNav),
        reason: 'expected a fresh loadNewerEvents call re-covering the '
            'focused month after the provider reset, with no further '
            'page change');

    final finalState = container.read(dashboardProvider).value!;
    expect(
      finalState.events.any((e) => e.key.startsWith('resume-recover-')),
      isTrue,
      reason: 'the re-covered batch must be merged into dashboard state',
    );
  });
}
