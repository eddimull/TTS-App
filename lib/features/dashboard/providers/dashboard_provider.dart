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

  /// Fetches the next-older 30-day window of events and merges them into the
  /// current state. Idempotent and self-guarding:
  /// - no-op while a fetch is in flight ([DashboardState.isLoadingOlder]),
  /// - no-op once history is exhausted ([DashboardState.hasReachedStart]),
  /// - merges by event id so overlapping day boundaries never duplicate.
  /// [loadedFrom] only ever moves backward (by 30 days per successful fetch).
  Future<void> loadOlder() async {
    final current = state.value;
    if (current == null) return;
    if (current.isLoadingOlder || current.hasReachedStart) return;

    state = AsyncValue.data(current.copyWith(isLoadingOlder: true));

    try {
      final repo = ref.read(dashboardRepositoryProvider);
      final older =
          await repo.loadOlderEvents(current.loadedFrom.toIso8601String());

      // Dedup only among events that have an id; events without one (e.g. some
      // rehearsal/scheduled shapes) are always kept — collapsing them by a
      // shared null id would silently drop distinct events.
      final existingIds =
          current.events.map((e) => e.id).whereType<int>().toSet();
      final merged = [
        ...current.events,
        ...older.where((e) => e.id == null || !existingIds.contains(e.id)),
      ];

      state = AsyncValue.data(current.copyWith(
        events: merged,
        loadedFrom: current.loadedFrom.subtract(const Duration(days: 30)),
        isLoadingOlder: false,
        hasReachedStart: older.isEmpty,
      ));
    } catch (_) {
      state = AsyncValue.data(
        (state.value ?? current).copyWith(isLoadingOlder: false),
      );
    }
  }

  /// Ensures the WHOLE of [focusedDay]'s month is loaded, fetching older chunks
  /// as needed. Fetches when the focused month's first day is strictly before
  /// the (day-granular) [DashboardState.loadedFrom] watermark — so forward
  /// navigation, or returning into a fully-loaded range, never triggers a fetch.
  ///
  /// The initial window starts mid-month (today − 30d), so the watermark's own
  /// month is only partially loaded. Comparing the month's FIRST day against the
  /// day-granular watermark means swiping into that month backfills its earlier
  /// days rather than leaving them blank. Loops to cover multi-month jumps,
  /// stopping when covered or history is exhausted.
  Future<void> ensureMonthLoaded(DateTime focusedDay) async {
    final monthStart = DateTime(focusedDay.year, focusedDay.month, 1);

    while (true) {
      final current = state.value;
      if (current == null) return;
      if (current.hasReachedStart) return;
      if (!monthStart.isBefore(current.loadedFrom)) return; // already covered

      final fromBefore = current.loadedFrom;
      await loadOlder();

      final after = state.value;
      // Guard against non-progress (e.g. an errored fetch left loadedFrom put):
      // if the watermark didn't move and start wasn't reached, stop to avoid a
      // hot loop. The next swipe can retry.
      if (after == null) return;
      if (after.hasReachedStart) return;
      if (!after.loadedFrom.isBefore(fromBefore)) return;
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final dashboardProvider =
    AsyncNotifierProvider<DashboardNotifier, DashboardState>(
  DashboardNotifier.new,
);
