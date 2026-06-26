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
  }) : super(_throwingDio);

  final List<EventSummary> initialEvents;

  /// Successive responses for each loadOlderEvents call, in order. When
  /// exhausted, returns an empty list (signals start-of-history).
  final List<List<EventSummary>> olderBatches;

  final List<String> requestedBeforeDates = [];
  int _batchIndex = 0;

  @override
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard() async =>
          (events: initialEvents, upcomingCharts: const <UpcomingChart>[]);

  @override
  Future<List<EventSummary>> loadOlderEvents(String beforeDate) async {
    requestedBeforeDates.add(beforeDate);
    if (_batchIndex >= olderBatches.length) return const [];
    return olderBatches[_batchIndex++];
  }
}

// selectedBandProvider is AsyncNotifierProvider<SelectedBandNotifier, int?>.
class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 10;
}

void main() {
  group('DashboardState.copyWith', () {
    test('defaults: empty, not loading older, start not reached', () {
      final from = DateTime(2026, 6, 1);
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: from,
      );

      expect(state.events, isEmpty);
      expect(state.loadedFrom, from);
      expect(state.isLoadingOlder, isFalse);
      expect(state.hasReachedStart, isFalse);
    });

    test('copyWith overrides only the named fields', () {
      final from = DateTime(2026, 6, 1);
      final earlier = DateTime(2026, 5, 2);
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: from,
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
}
