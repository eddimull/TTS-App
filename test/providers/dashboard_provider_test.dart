import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';
import 'package:tts_bandmate/features/dashboard/data/models/upcoming_chart.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

// ── Fake repository ───────────────────────────────────────────────────────────

class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository({
    required List<EventSummary> events,
    required List<UpcomingChart> charts,
  })  : _events = events,
        _charts = charts;

  final List<EventSummary> _events;
  final List<UpcomingChart> _charts;
  int callCount = 0;

  @override
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard() async {
    callCount++;
    return (events: _events, upcomingCharts: _charts);
  }
}

// Expose internal Dio field to satisfy the interface — not used by the fake.
extension on FakeDashboardRepository {
  dynamic get dio => throw UnimplementedError();
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

EventSummary _makeEvent(String key) => EventSummary.fromJson({
      'id': key.hashCode.abs(),
      'key': key,
      'title': 'Event $key',
      'date': '2026-04-15',
      'event_source': 'booking',
    });

UpcomingChart _makeChart(String title) => UpcomingChart.fromJson({
      'type': 'chart',
      'title': title,
      'event_title': 'Some Gig',
      'event_date': '2026-04-15',
    });

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('DashboardNotifier', () {
    ProviderContainer makeContainer(FakeDashboardRepository repo) {
      return ProviderContainer(
        overrides: [
          dashboardRepositoryProvider.overrideWithValue(repo),
        ],
      );
    }

    test('test_build_loads_events_and_charts', () async {
      final repo = FakeDashboardRepository(
        events: [_makeEvent('e1'), _makeEvent('e2')],
        charts: [_makeChart('My Way')],
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final state = await container.read(dashboardProvider.future);

      expect(state.events, hasLength(2));
      expect(state.events.first.key, 'e1');
      expect(state.upcomingCharts, hasLength(1));
      expect(state.upcomingCharts.first.title, 'My Way');
    });

    test('test_build_returns_empty_lists_when_no_data', () async {
      final repo = FakeDashboardRepository(events: [], charts: []);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final state = await container.read(dashboardProvider.future);

      expect(state.events, isEmpty);
      expect(state.upcomingCharts, isEmpty);
    });

    test('test_refresh_re_fetches_from_repository', () async {
      final repo = FakeDashboardRepository(
        events: [_makeEvent('e1')],
        charts: [],
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      // First load via build()
      await container.read(dashboardProvider.future);
      expect(repo.callCount, 1);

      // Trigger refresh
      await container.read(dashboardProvider.notifier).refresh();
      expect(repo.callCount, 2);
    });

    test('test_build_propagates_repository_error', () async {
      // Repository that always throws
      final container = ProviderContainer(
        overrides: [
          dashboardRepositoryProvider.overrideWith((ref) {
            return _ThrowingDashboardRepository();
          }),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(dashboardProvider.future).then(
            (_) => 'ok',
            onError: (_) => 'error',
          );

      expect(result, 'error');
    });
  });
}

class _ThrowingDashboardRepository implements DashboardRepository {
  @override
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard() async {
    throw Exception('Network error');
  }
}
