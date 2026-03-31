import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dashboard_repository.dart';
import '../data/models/upcoming_chart.dart';
import '../../events/data/models/event_summary.dart';
import '../../../shared/providers/selected_band_provider.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class DashboardState {
  const DashboardState({
    required this.events,
    required this.upcomingCharts,
  });

  final List<EventSummary> events;
  final List<UpcomingChart> upcomingCharts;

  /// Returns the event that is currently in progress, or null.
  ///
  /// An event is considered "live" when:
  /// - Its date matches today, AND
  /// - If a start time is present: now falls within [startTime, startTime + 4h].
  /// - If no start time: the whole calendar day counts.
  EventSummary? get currentEvent {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    for (final event in events) {
      final eventDate = DateTime(
        event.parsedDate.year,
        event.parsedDate.month,
        event.parsedDate.day,
      );
      if (eventDate != todayDate) continue;

      final rawTime = event.time;
      if (rawTime == null || rawTime.isEmpty) {
        // No start time — treat the entire day as the window.
        return event;
      }

      // Parse "HH:mm" into a full DateTime for today.
      final parts = rawTime.split(':');
      if (parts.length < 2) return event; // unparseable — include it
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return event;

      final start = DateTime(now.year, now.month, now.day, h, m);
      // Default performance window: 4 hours after start.
      final end = start.add(const Duration(hours: 4));

      if (!now.isBefore(start) && now.isBefore(end)) return event;
    }
    return null;
  }

  @override
  String toString() =>
      'DashboardState(events: ${events.length}, charts: ${upcomingCharts.length})';
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class DashboardNotifier extends AsyncNotifier<DashboardState> {
  @override
  Future<DashboardState> build() async {
    // Wait for band selection to resolve before fetching — avoids a missing
    // X-Band-ID header on the first request when storage hasn't been read yet.
    final bandId = await ref.watch(selectedBandProvider.future);
    if (bandId == null) return const DashboardState(events: [], upcomingCharts: []);

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
