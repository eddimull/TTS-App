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
    required this.loadedFrom,
    this.isLoadingOlder = false,
    this.hasReachedStart = false,
  });

  final List<EventSummary> events;
  final List<UpcomingChart> upcomingCharts;

  /// Earliest date for which events are currently loaded. Only ever moves
  /// backward (see [DashboardNotifier.loadOlder]). The calendar uses this as a
  /// watermark to decide whether swiping to a month needs an older fetch.
  final DateTime loadedFrom;

  /// True while an older-events fetch is in flight; guards against duplicate
  /// concurrent fetches and drives the loading indicator.
  final bool isLoadingOlder;

  /// True once an older fetch returned zero events — there is no more history
  /// to load, so further back-fetches are skipped.
  final bool hasReachedStart;

  DashboardState copyWith({
    List<EventSummary>? events,
    List<UpcomingChart>? upcomingCharts,
    DateTime? loadedFrom,
    bool? isLoadingOlder,
    bool? hasReachedStart,
  }) {
    return DashboardState(
      events: events ?? this.events,
      upcomingCharts: upcomingCharts ?? this.upcomingCharts,
      loadedFrom: loadedFrom ?? this.loadedFrom,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      hasReachedStart: hasReachedStart ?? this.hasReachedStart,
    );
  }

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
  /// Days of past events the initial payload covers — must match the backend
  /// DashboardController::INITIAL_PAST_WINDOW_DAYS.
  static const int _initialPastWindowDays = 30;

  /// Truncates a [DateTime] to midnight (date-only) for stable comparisons.
  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  @override
  Future<DashboardState> build() async {
    final initialFrom = _dateOnly(
      DateTime.now().subtract(const Duration(days: _initialPastWindowDays)),
    );

    // Wait for band selection to resolve before fetching — avoids a missing
    // X-Band-ID header on the first request when storage hasn't been read yet.
    final bandId = await ref.watch(selectedBandProvider.future);
    if (bandId == null) {
      return DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: initialFrom,
      );
    }

    final repo = ref.watch(dashboardRepositoryProvider);
    final result = await repo.getDashboard();
    return DashboardState(
      events: result.events,
      upcomingCharts: result.upcomingCharts,
      loadedFrom: initialFrom,
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
        loadedFrom: _dateOnly(
          DateTime.now().subtract(const Duration(days: _initialPastWindowDays)),
        ),
      );
    });
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final dashboardProvider =
    AsyncNotifierProvider<DashboardNotifier, DashboardState>(
  DashboardNotifier.new,
);
