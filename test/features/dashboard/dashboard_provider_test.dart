import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';
import 'package:tts_bandmate/features/dashboard/data/models/upcoming_chart.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

final _throwingDio = Dio();

// EventSummary.fromJson does non-null casts on 'key' and 'title' — both required.
EventSummary _event(int id, String date) => EventSummary.fromJson({
      'id': id,
      'key': 'evt-$id',
      'title': 'Event $id',
      'date': date,
      'event_source': 'booking',
    });

/// Fake repository: records requested before_dates, returns scripted batches.
class _FakeDashboardRepository extends DashboardRepository {
  _FakeDashboardRepository({
    required this.initialEvents,
    required this.olderBatches,
    this.newerBatches = const [],
  }) : super(_throwingDio);

  final List<EventSummary> initialEvents;

  /// Successive responses for each loadOlderEvents call, in order. When
  /// exhausted, returns an empty list (signals start-of-history).
  final List<List<EventSummary>> olderBatches;

  /// Successive responses for each loadNewerEvents call, in order. When
  /// exhausted, returns an empty list.
  final List<List<EventSummary>> newerBatches;

  final List<String> requestedBeforeDates = [];
  final List<(String, String)> requestedNewerWindows = [];
  final List<String?> requestedTos = [];
  int _batchIndex = 0;
  int _newerIndex = 0;

  @override
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard({String? to}) async {
    requestedTos.add(to);
    return (events: initialEvents, upcomingCharts: const <UpcomingChart>[]);
  }

  @override
  Future<List<EventSummary>> loadOlderEvents(String beforeDate) async {
    requestedBeforeDates.add(beforeDate);
    if (_batchIndex >= olderBatches.length) return const [];
    return olderBatches[_batchIndex++];
  }

  @override
  Future<List<EventSummary>> loadNewerEvents(
      String afterDate, String beforeDate) async {
    requestedNewerWindows.add((afterDate, beforeDate));
    if (_newerIndex >= newerBatches.length) return const [];
    return newerBatches[_newerIndex++];
  }
}

// selectedBandProvider is AsyncNotifierProvider<SelectedBandNotifier, int?>.
class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 10;
}

/// Fake repository whose loadOlderEvents call resolves only when the test
/// completes [olderCompleter] — used to force a deterministic race between a
/// pending loadOlder() and a loadNewerEvents call that resolves first.
class _RaceDashboardRepository extends DashboardRepository {
  _RaceDashboardRepository({
    required this.initialEvents,
    required this.olderCompleter,
    required this.newerResult,
  }) : super(_throwingDio);

  final List<EventSummary> initialEvents;
  final Completer<List<EventSummary>> olderCompleter;
  final List<EventSummary> newerResult;

  @override
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard({String? to}) async {
    return (events: initialEvents, upcomingCharts: const <UpcomingChart>[]);
  }

  @override
  Future<List<EventSummary>> loadOlderEvents(String beforeDate) {
    return olderCompleter.future;
  }

  @override
  Future<List<EventSummary>> loadNewerEvents(
      String afterDate, String beforeDate) async {
    return newerResult;
  }
}

void main() {
  group('DashboardState.coversMonth', () {
    test('month fully inside the loaded window returns true', () {
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: DateTime(2026, 6, 1),
        loadedTo: DateTime(2026, 9, 1),
      );

      expect(state.coversMonth(DateTime(2026, 7, 15)), isTrue);
    });

    test('month straddling loadedTo returns false', () {
      // loadedTo lands mid-month (Aug 15), so August itself is not fully
      // covered even though it starts before the watermark.
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: DateTime(2026, 6, 1),
        loadedTo: DateTime(2026, 8, 15),
      );

      expect(state.coversMonth(DateTime(2026, 8, 10)), isFalse);
    });

    test('month straddling loadedFrom returns false', () {
      // loadedFrom lands mid-month (Jun 10), so June itself is not fully
      // covered even though it ends before the watermark.
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: DateTime(2026, 6, 10),
        loadedTo: DateTime(2026, 9, 1),
      );

      expect(state.coversMonth(DateTime(2026, 6, 20)), isFalse);
    });

    test('loadedTo-exclusive edge: nextMonthFirst == loadedTo returns true',
        () {
      // loadedTo is exclusive — events on/after it are NOT loaded — but the
      // month whose exclusive end exactly equals loadedTo is still fully
      // covered, since every day in it is strictly before loadedTo.
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: DateTime(2026, 6, 1),
        loadedTo: DateTime(2026, 9, 1),
      );

      expect(state.coversMonth(DateTime(2026, 8, 15)), isTrue);
    });

    test('loadedFrom-inclusive edge: monthStart == loadedFrom returns true',
        () {
      // loadedFrom is inclusive of its own day — a month whose first day
      // exactly equals loadedFrom is fully covered, not excluded.
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: DateTime(2026, 6, 1),
        loadedTo: DateTime(2026, 9, 1),
      );

      expect(state.coversMonth(DateTime(2026, 6, 15)), isTrue);
    });
  });

  group('DashboardState.copyWith', () {
    test('defaults: empty, not loading older, start not reached', () {
      final from = DateTime(2026, 6, 1);
      final to = DateTime(2026, 9, 1);
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: from,
        loadedTo: to,
      );

      expect(state.events, isEmpty);
      expect(state.loadedFrom, from);
      expect(state.loadedTo, to);
      expect(state.isLoadingOlder, isFalse);
      expect(state.hasReachedStart, isFalse);
      expect(state.isLoadingNewer, isFalse);
    });

    test('copyWith overrides only the named fields', () {
      final from = DateTime(2026, 6, 1);
      final to = DateTime(2026, 9, 1);
      final earlier = DateTime(2026, 5, 2);
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: from,
        loadedTo: to,
      );

      final next = state.copyWith(
        loadedFrom: earlier,
        isLoadingOlder: true,
        hasReachedStart: true,
      );

      expect(next.loadedFrom, earlier);
      expect(next.isLoadingOlder, isTrue);
      expect(next.hasReachedStart, isTrue);
      expect(next.events, same(state.events));
      expect(next.upcomingCharts, same(state.upcomingCharts));
    });
  });

  group('DashboardNotifier.loadOlder', () {
    late ProviderContainer container;
    late _FakeDashboardRepository fakeRepo;

    Future<DashboardNotifier> buildNotifier() async {
      final notifier = container.read(dashboardProvider.notifier);
      await container.read(dashboardProvider.future); // resolve build()
      return notifier;
    }

    void setUpContainer(_FakeDashboardRepository repo) {
      fakeRepo = repo;
      container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(repo),
        selectedBandProvider.overrideWith(() => _StubBand()),
      ]);
      addTearDown(container.dispose);
    }

    test('merges and dedups older events by id', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: [_event(1, '2026-06-20')],
        olderBatches: [
          [_event(1, '2026-06-20'), _event(2, '2026-05-15')],
        ],
      ));
      final notifier = await buildNotifier();

      await notifier.loadOlder();

      final state = container.read(dashboardProvider).value!;
      final ids = state.events.map((e) => e.id).toList()..sort();
      expect(ids, [1, 2], reason: 'duplicate id 1 must not be added twice');
    });

    test('keeps distinct null-id events instead of collapsing them', () async {
      // Events without an id (e.g. some rehearsal/scheduled shapes) must not be
      // deduped against each other — they'd all share a null id and vanish.
      EventSummary nullIdEvent(String key, String date) =>
          EventSummary.fromJson({
            'key': key,
            'title': 'Event $key',
            'date': date,
            'event_source': 'rehearsal',
          });

      setUpContainer(_FakeDashboardRepository(
        initialEvents: [nullIdEvent('a', '2026-06-20')],
        olderBatches: [
          [nullIdEvent('b', '2026-05-15'), nullIdEvent('c', '2026-05-16')],
        ],
      ));
      final notifier = await buildNotifier();

      await notifier.loadOlder();

      final state = container.read(dashboardProvider).value!;
      expect(state.events.length, 3,
          reason: 'all three null-id events must be retained');
      expect(state.events.every((e) => e.id == null), isTrue);
    });

    test('loadedFrom decrements by 30 days per fetch', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: [
          [_event(2, '2026-05-15')],
        ],
      ));
      final notifier = await buildNotifier();
      final before = container.read(dashboardProvider).value!.loadedFrom;

      await notifier.loadOlder();

      final after = container.read(dashboardProvider).value!.loadedFrom;
      expect(before.difference(after).inDays, 30);
    });

    test('sets hasReachedStart when a fetch returns no events', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: const [],
      ));
      final notifier = await buildNotifier();

      await notifier.loadOlder();

      final state = container.read(dashboardProvider).value!;
      expect(state.hasReachedStart, isTrue);
    });

    test('does not fetch again once hasReachedStart is set', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: const [],
      ));
      final notifier = await buildNotifier();

      await notifier.loadOlder();
      await notifier.loadOlder();

      expect(fakeRepo.requestedBeforeDates.length, 1);
    });
  });

  group('DashboardNotifier.loadNewer', () {
    late ProviderContainer container;
    late _FakeDashboardRepository fakeRepo;

    Future<DashboardNotifier> buildNotifier() async {
      final notifier = container.read(dashboardProvider.notifier);
      await container.read(dashboardProvider.future); // resolve build()
      return notifier;
    }

    void setUpContainer(_FakeDashboardRepository repo) {
      fakeRepo = repo;
      container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(repo),
        selectedBandProvider.overrideWith(() => _StubBand()),
      ]);
      addTearDown(container.dispose);
    }

    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    test('initial fetch sends to = today + 90d', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: [], olderBatches: [],
      ));
      await buildNotifier();

      final expected = ymd(DateTime.now().add(const Duration(days: 90)));
      expect(fakeRepo.requestedTos, [expected]);
    });

    test('forward ensureMonthLoaded fetches one window to the month start after target', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: [], olderBatches: [],
        newerBatches: [
          [_event(5, '2028-03-10')],
        ],
      ));
      final notifier = await buildNotifier();

      // Jump 2+ years forward — must be a single fetch, not many.
      final target = DateTime(2028, 3, 15);
      await notifier.ensureMonthLoaded(target);

      expect(fakeRepo.requestedNewerWindows, hasLength(1));
      final (after, before) = fakeRepo.requestedNewerWindows.single;
      expect(after, ymd(DateTime.now().add(const Duration(days: 90))),
          reason: 'window starts at the current loadedTo watermark');
      expect(before, '2028-04-01',
          reason: 'window extends to the first day of the month after target');

      final state = container.read(dashboardProvider).value!;
      expect(state.events.map((e) => e.id), contains(5));
      expect(state.loadedTo, DateTime(2028, 4, 1));
    });

    test('already-covered months trigger no fetch and empty windows do not stop future fetches', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: [], olderBatches: [],
        newerBatches: [], // every loadNewer returns empty
      ));
      final notifier = await buildNotifier();

      await notifier.ensureMonthLoaded(DateTime(2027, 6, 15));
      expect(fakeRepo.requestedNewerWindows, hasLength(1));

      // Same month again: covered, no new fetch.
      await notifier.ensureMonthLoaded(DateTime(2027, 6, 20));
      expect(fakeRepo.requestedNewerWindows, hasLength(1));

      // Further month: MUST fetch again despite the last window being empty —
      // there is no hasReachedEnd for the future.
      await notifier.ensureMonthLoaded(DateTime(2028, 1, 10));
      expect(fakeRepo.requestedNewerWindows, hasLength(2));
    });

    test('merges newer events deduping by id and by key for null-id events', () async {
      EventSummary nullIdEvent(String key, String date) =>
          EventSummary.fromJson({
            'key': key,
            'title': 'Event $key',
            'date': date,
            'event_source': 'rehearsal',
          });

      setUpContainer(_FakeDashboardRepository(
        initialEvents: [_event(1, '2026-08-01'), nullIdEvent('vr-a', '2026-08-05')],
        olderBatches: [],
        newerBatches: [
          [
            _event(1, '2026-08-01'), // dup by id — dropped
            nullIdEvent('vr-a', '2026-08-05'), // dup by key — dropped
            nullIdEvent('vr-b', '2026-11-12'), // new — kept
            _event(2, '2026-12-01'), // new — kept
          ],
        ],
      ));
      final notifier = await buildNotifier();

      await notifier.ensureMonthLoaded(DateTime(2026, 12, 15));

      final state = container.read(dashboardProvider).value!;
      expect(state.events, hasLength(4));
    });

    test('refresh resets the forward watermark', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: [], olderBatches: [], newerBatches: [],
      ));
      final notifier = await buildNotifier();
      await notifier.ensureMonthLoaded(DateTime(2028, 3, 15));

      await notifier.refresh();

      final state = container.read(dashboardProvider).value!;
      final expected = DateTime.now().add(const Duration(days: 90));
      expect(state.loadedTo.year, expected.year);
      expect(state.loadedTo.month, expected.month);
      expect(state.loadedTo.day, expected.day);
      // And the refresh re-sent to=.
      expect(fakeRepo.requestedTos, hasLength(2));
    });
  });

  group('DashboardNotifier.ensureMonthLoaded (watermark trigger)', () {
    late ProviderContainer container;
    late _FakeDashboardRepository fakeRepo;

    Future<DashboardNotifier> build(_FakeDashboardRepository repo) async {
      fakeRepo = repo;
      container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(repo),
        selectedBandProvider.overrideWith(() => _StubBand()),
      ]);
      addTearDown(container.dispose);
      final notifier = container.read(dashboardProvider.notifier);
      await container.read(dashboardProvider.future);
      return notifier;
    }

    test('forward-then-back within fully-loaded range fetches nothing', () async {
      final notifier = await build(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: [
          [_event(2, '2026-05-15')],
        ],
      ));
      final loadedFrom = container.read(dashboardProvider).value!.loadedFrom;

      // Forward two months (fully loaded) then back one month — both are after
      // the watermark, so still fully loaded. No fetch.
      await notifier.ensureMonthLoaded(
        DateTime(loadedFrom.year, loadedFrom.month + 2, 1),
      );
      await notifier.ensureMonthLoaded(
        DateTime(loadedFrom.year, loadedFrom.month + 1, 1),
      );

      expect(fakeRepo.requestedBeforeDates, isEmpty);
    });

    test('swiping into the partial watermark month backfills it once', () async {
      // The initial window starts mid-month (today − 30d), so the watermark's
      // own month is only partially loaded. Swiping into it must fetch exactly
      // once to fill the earlier days — then not fetch again on a revisit.
      final notifier = await build(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: [
          [_event(2, '2026-05-15')],
        ],
      ));
      final loadedFrom = container.read(dashboardProvider).value!.loadedFrom;
      // Only run the meaningful assertion when the watermark is genuinely
      // mid-month; if today happens to be the 1st, loadedFrom is month-aligned
      // and there is nothing to backfill.
      if (loadedFrom.day == 1) return;

      await notifier.ensureMonthLoaded(
        DateTime(loadedFrom.year, loadedFrom.month, 1),
      );
      expect(fakeRepo.requestedBeforeDates.length, 1,
          reason: 'partial watermark month should backfill exactly once');

      // Revisiting the same month does not fetch again (watermark moved back).
      await notifier.ensureMonthLoaded(
        DateTime(loadedFrom.year, loadedFrom.month, 1),
      );
      expect(fakeRepo.requestedBeforeDates.length, 1,
          reason: 'revisit must not re-fetch');
    });

    test('two-back then one-forward fetches each chunk exactly once', () async {
      final notifier = await build(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: [
          [_event(2, '2026-05-15')],
          [_event(3, '2026-04-15')],
        ],
      ));
      final loadedFrom = container.read(dashboardProvider).value!.loadedFrom;

      await notifier.ensureMonthLoaded(
        DateTime(loadedFrom.year, loadedFrom.month - 2, 1),
      );
      final fetchesAfterBack = fakeRepo.requestedBeforeDates.length;
      expect(fetchesAfterBack, greaterThanOrEqualTo(2));

      await notifier.ensureMonthLoaded(
        DateTime(loadedFrom.year, loadedFrom.month - 1, 1),
      );
      expect(fakeRepo.requestedBeforeDates.length, fetchesAfterBack);

      for (var i = 1; i < fakeRepo.requestedBeforeDates.length; i++) {
        final prev = DateTime.parse(fakeRepo.requestedBeforeDates[i - 1]);
        final curr = DateTime.parse(fakeRepo.requestedBeforeDates[i]);
        expect(curr.isBefore(prev), isTrue);
      }
    });

    test('stops looping when hasReachedStart even if month not covered', () async {
      final notifier = await build(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: const [],
      ));
      final loadedFrom = container.read(dashboardProvider).value!.loadedFrom;

      await notifier.ensureMonthLoaded(
        DateTime(loadedFrom.year - 1, loadedFrom.month, 1),
      );

      expect(fakeRepo.requestedBeforeDates.length, 1);
      expect(container.read(dashboardProvider).value!.hasReachedStart, isTrue);
    });
  });

  group('DashboardNotifier concurrency (loadOlder x _loadNewer race)', () {
    test(
        'loadOlder completing after a concurrent _loadNewer preserves both merges',
        () async {
      final olderCompleter = Completer<List<EventSummary>>();
      final repo = _RaceDashboardRepository(
        initialEvents: [_event(1, '2026-06-20')],
        olderCompleter: olderCompleter,
        newerResult: [_event(3, '2026-12-05')],
      );

      final container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(repo),
        selectedBandProvider.overrideWith(() => _StubBand()),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(dashboardProvider.notifier);
      await container.read(dashboardProvider.future); // resolve build()

      final beforeState = container.read(dashboardProvider).value!;
      final expectedLoadedFrom =
          beforeState.loadedFrom.subtract(const Duration(days: 30));

      // Start loadOlder() — its repo call hangs on olderCompleter.
      final olderFuture = notifier.loadOlder();

      // While loadOlder is still in flight, kick off and fully await a
      // _loadNewer via ensureMonthLoaded — its fake resolves immediately, so
      // this completes and mutates state BEFORE loadOlder finishes.
      final target = DateTime(2026, 12, 15);
      await notifier.ensureMonthLoaded(target);

      final midState = container.read(dashboardProvider).value!;
      expect(midState.events.map((e) => e.id), contains(3),
          reason: '_loadNewer must have merged its batch already');
      expect(midState.isLoadingNewer, isFalse);
      expect(midState.isLoadingOlder, isTrue,
          reason: 'loadOlder is still pending at this point');

      // Now let loadOlder's repo call resolve and await its completion.
      olderCompleter.complete([_event(2, '2026-05-15')]);
      await olderFuture;

      final finalState = container.read(dashboardProvider).value!;
      final ids = finalState.events.map((e) => e.id).toSet();

      expect(ids, containsAll([1, 2, 3]),
          reason:
              'both the older batch (id 2) and newer batch (id 3) must survive '
              '— a stale pre-await snapshot in loadOlder must not clobber the '
              'newer merge that completed first');
      expect(finalState.loadedFrom, expectedLoadedFrom,
          reason: 'loadedFrom must move backward from the older fetch');
      expect(finalState.loadedTo, DateTime(2027, 1, 1),
          reason: 'loadedTo must move forward to the newer fetch target '
              '(first day of the month after the focused month)');
      expect(finalState.isLoadingOlder, isFalse);
      expect(finalState.isLoadingNewer, isFalse);
    });
  });
}
