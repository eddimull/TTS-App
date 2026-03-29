import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dashboard_repository.dart';
import '../data/models/upcoming_chart.dart';
import '../../events/data/models/event_summary.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class DashboardState {
  const DashboardState({
    required this.events,
    required this.upcomingCharts,
  });

  final List<EventSummary> events;
  final List<UpcomingChart> upcomingCharts;

  @override
  String toString() =>
      'DashboardState(events: ${events.length}, charts: ${upcomingCharts.length})';
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class DashboardNotifier extends AsyncNotifier<DashboardState> {
  @override
  Future<DashboardState> build() async {
    final repo = ref.watch(dashboardRepositoryProvider);
    final result = await repo.getDashboard();
    return DashboardState(
      events: result.events,
      upcomingCharts: result.upcomingCharts,
    );
  }

  /// Re-fetches the dashboard from the server.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(dashboardRepositoryProvider);
      final result = await repo.getDashboard();
      return DashboardState(
        events: result.events,
        upcomingCharts: result.upcomingCharts,
      );
    });
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final dashboardProvider =
    AsyncNotifierProvider<DashboardNotifier, DashboardState>(
  DashboardNotifier.new,
);
