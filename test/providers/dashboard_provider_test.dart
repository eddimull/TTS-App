import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';
import 'package:tts_bandmate/features/dashboard/data/models/upcoming_chart.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

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
          // Bypass SecureStorage / FlutterSecureStorage in unit tests.
          selectedBandProvider.overrideWith(() => _FakeSelectedBandNotifier()),
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
          selectedBandProvider.overrideWith(() => _FakeSelectedBandNotifier()),
          dashboardRepositoryProvider.overrideWith((ref) {
            return _ThrowingDashboardRepository();
          }),
        ],
      );
      addTearDown(container.dispose);

      // Trigger computation and let the provider settle to an error state.
      await Future.microtask(() => container.read(dashboardProvider));
      await Future<void>.delayed(Duration.zero);
      final settled = container.read(dashboardProvider);
      expect(settled.hasError, isTrue);
    });
  });
}

class _FakeSelectedBandNotifier extends AsyncNotifier<int?>
    implements SelectedBandNotifier {
  @override
  Future<int?> build() async => 1; // pretend band 1 is always selected

  @override
  Future<void> selectBand(int id) async {}

  @override
  Future<void> clear() async {}
}

class _ThrowingDashboardRepository implements DashboardRepository {
  @override
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard() async {
    throw Exception('Network error');
  }
}
