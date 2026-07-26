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

import 'dart:async';

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

/// Fake repository whose loadNewerEvents always throws — used to reproduce
/// the retry-storm bug: a permanently failing forward fetch must not be
/// auto-retried indefinitely by the resume-recover listener.
class _ThrowingNewerDashboardRepository extends DashboardRepository {
  _ThrowingNewerDashboardRepository() : super(_throwingDio);

  int loadNewerCallCount = 0;
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
    loadNewerCallCount++;
    throw Exception('simulated permanent forward-fetch failure');
  }
}

/// Replicates DashboardScreen's exact resume-recover wiring, but against a
/// plain ProviderContainer instead of a widget tree: on every dashboardProvider
/// state change, ask shouldRecoverFocusedMonth() whether to retry, and if so
/// call ensureMonthLoaded(focusedDay) — exactly like the ref.listen callback
/// in lib/features/dashboard/screens/dashboard_screen.dart.
///
/// This avoids driving the real TableCalendar for the retry-storm scenario:
/// under the pre-fix bug, a single tester.pump(duration) can spin forever
/// internally (each retry synchronously reschedules the next one within the
/// same pump call), so no bounded sequence of widget pumps is safe to await.
/// A container-level test with an explicit, awaited call sequence gives full
/// determinism without any Flutter frame/duration machinery. It exercises
/// the *actual* shouldRecoverFocusedMonth() function the screen calls, not a
/// reimplementation of its logic.
void _wireResumeRecoverListener(
  ProviderContainer container,
  DateTime Function() getFocusedDay,
) {
  DashboardState? previous;
  container.listen<AsyncValue<DashboardState>>(
    dashboardProvider,
    (prev, next) {
      final state = next.value;
      if (state == null) return;
      final shouldRecover = shouldRecoverFocusedMonth(
        previous: previous,
        next: state,
        focusedDay: getFocusedDay(),
      );
      previous = state;
      if (!shouldRecover) return;
      unawaited(
        container.read(dashboardProvider.notifier).ensureMonthLoaded(
              getFocusedDay(),
            ),
      );
    },
    fireImmediately: false,
  );
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

  group('resume-recover listener retry-storm guard', () {
    // NOTE ON TEST STRATEGY: this scenario is deliberately NOT a widget test
    // driving the real TableCalendar. The retry storm this guards against is
    // a genuine, self-sustaining synchronous-ish loop (each failed fetch's
    // state change re-triggers the next fetch within the same event-loop
    // turn) — under the pre-fix code, a single `tester.pump(duration)` call
    // can spin forever internally before ever returning control to the test,
    // so no bounded *count* of awaited pump calls is safe: even the very
    // first duration-bearing pump after crossing into an uncovered month can
    // hang indefinitely. This was verified empirically while developing the
    // test (pump(Duration.zero) / no-arg pump() never advance the chain at
    // all; pump(milliseconds: 20) already hangs).
    //
    // Instead, this test exercises the exact same decision function the
    // screen's ref.listen calls (shouldRecoverFocusedMonth, wired up via
    // _wireResumeRecoverListener above) against a plain ProviderContainer.
    // Every step is an explicitly awaited notifier call, so the test is
    // fully deterministic and cannot hang: if a step doesn't stop retrying
    // on its own, this test's own assertions — not an unbounded pump loop —
    // catch it.
    late ProviderContainer container;
    late _ThrowingNewerDashboardRepository repo;
    late DateTime focusedDay;

    setUp(() {
      repo = _ThrowingNewerDashboardRepository();
      container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(repo),
        selectedBandProvider.overrideWith(() => _StubBand()),
      ]);
      addTearDown(container.dispose);
    });

    test(
        'a permanently failing forward fetch on an uncovered month is not '
        'auto-retried indefinitely by the resume-recover listener',
        () async {
      // Resolve build() and park focusedDay on a month far beyond the
      // initial ~90-day window — permanently uncovered given loadNewerEvents
      // always throws.
      await container.read(dashboardProvider.future);
      final loadedTo = container.read(dashboardProvider).value!.loadedTo;
      focusedDay = DateTime(loadedTo.year, loadedTo.month + 6, 15);

      _wireResumeRecoverListener(container, () => focusedDay);

      // Simulate the initial page-change onto the uncovered month: this is
      // the direct analogue of onPageChanged -> ensureMonthLoaded in the
      // screen. It fails once (loadNewerEvents throws), which IS itself a
      // dashboardProvider state change (isLoadingNewer true->false) that
      // the listener observes.
      await container
          .read(dashboardProvider.notifier)
          .ensureMonthLoaded(focusedDay);

      final callsAfterInitialPage = repo.loadNewerCallCount;
      expect(callsAfterInitialPage, greaterThan(0),
          reason: 'the initial page-change must have attempted at least '
              'one loadNewerEvents call');

      // Let the listener's reaction to that failure's state change run to
      // completion before asserting — the listener's unawaited() call
      // dispatches a microtask; await a real Future to flush it.
      await Future<void>.delayed(Duration.zero);
      final callsAfterListenerReaction = repo.loadNewerCallCount;

      // The core regression assertion: the listener's own reaction to the
      // failed fetch must not itself trigger a further retry — this is
      // exactly the "completed without progress" transition from a fetch
      // the listener itself initiated on the prior state change. Without the
      // fix, this call count keeps climbing every time the loop below
      // flushes another microtask turn.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(repo.loadNewerCallCount, callsAfterListenerReaction,
          reason: 'no further loadNewerEvents calls should occur from the '
              'listener reacting to its own no-progress state change — an '
              'unbounded retry storm would keep incrementing this after '
              'every flushed microtask turn');

      // Now simulate the documented trigger: an app-resume blanket
      // invalidation while still parked on this permanently-uncovered
      // month.
      final callsBeforeInvalidate = repo.loadNewerCallCount;
      container.invalidate(dashboardProvider);
      await container.read(dashboardProvider.future); // resolve rebuilt build()
      await Future<void>.delayed(Duration.zero);

      final callsAfterInvalidateSettles = repo.loadNewerCallCount;
      expect(
        callsAfterInvalidateSettles,
        lessThanOrEqualTo(callsBeforeInvalidate + 1),
        reason: 'at most one retry should occur after the provider reset '
            '(the listener\'s single reaction to the reset itself)',
      );

      // Flush several more microtask turns — a storm would keep growing;
      // the fix must leave the count exactly where it settled.
      final callsBeforeFinalFlush = repo.loadNewerCallCount;
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(repo.loadNewerCallCount, callsBeforeFinalFlush,
          reason: 'call count must stay constant across further flushed '
              'microtask turns — an unbounded retry storm would keep '
              'incrementing it indefinitely');
    });
  });
}
