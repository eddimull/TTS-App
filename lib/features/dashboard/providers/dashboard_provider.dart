import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dashboard_repository.dart';
import '../data/models/upcoming_chart.dart';
import '../../events/data/models/event_summary.dart';
import '../../../shared/cache/api_cache_storage.dart';
import '../../../shared/cache/swr.dart';
import '../../../shared/providers/connectivity_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class DashboardState {
  const DashboardState({
    required this.events,
    required this.upcomingCharts,
    required this.loadedFrom,
    required this.loadedTo,
    this.isLoadingOlder = false,
    this.hasReachedStart = false,
    this.isLoadingNewer = false,
  });

  final List<EventSummary> events;
  final List<UpcomingChart> upcomingCharts;

  /// Earliest date for which events are currently loaded. Only ever moves
  /// backward (see [DashboardNotifier.loadOlder]). The calendar uses this as a
  /// watermark to decide whether swiping to a month needs an older fetch.
  final DateTime loadedFrom;

  /// Exclusive forward watermark: events on/after this date are NOT loaded
  /// yet. Only ever moves forward (see [DashboardNotifier._loadNewer]);
  /// [DashboardNotifier.refresh] resets it. There is deliberately no
  /// "reached end" flag — an empty forward window proves nothing about later
  /// events, so the browse cap is the calendar's lastDay.
  final DateTime loadedTo;

  /// True while an older-events fetch is in flight; guards against duplicate
  /// concurrent fetches and drives the loading indicator.
  final bool isLoadingOlder;

  /// True once an older fetch returned zero events — there is no more history
  /// to load, so further back-fetches are skipped.
  final bool hasReachedStart;

  /// True while a newer-events fetch is in flight.
  final bool isLoadingNewer;

  DashboardState copyWith({
    List<EventSummary>? events,
    List<UpcomingChart>? upcomingCharts,
    DateTime? loadedFrom,
    DateTime? loadedTo,
    bool? isLoadingOlder,
    bool? hasReachedStart,
    bool? isLoadingNewer,
  }) {
    return DashboardState(
      events: events ?? this.events,
      upcomingCharts: upcomingCharts ?? this.upcomingCharts,
      loadedFrom: loadedFrom ?? this.loadedFrom,
      loadedTo: loadedTo ?? this.loadedTo,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      hasReachedStart: hasReachedStart ?? this.hasReachedStart,
      isLoadingNewer: isLoadingNewer ?? this.isLoadingNewer,
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

  /// True when the WHOLE of [focusedDay]'s month lies inside the loaded
  /// window [loadedFrom, loadedTo). Months outside need an ensureMonthLoaded.
  bool coversMonth(DateTime focusedDay) {
    final monthStart = DateTime(focusedDay.year, focusedDay.month, 1);
    final nextMonthFirst = DateTime(focusedDay.year, focusedDay.month + 1, 1);
    return !monthStart.isBefore(loadedFrom) && !nextMonthFirst.isAfter(loadedTo);
  }
}

/// Decides whether a dashboard provider state transition should trigger an
/// `ensureMonthLoaded` retry for [focusedDay] — the decision behind the
/// resume-recover `ref.listen` in `DashboardScreen`.
///
/// Returns `false` (no retry) when:
/// - the focused month is already covered, or
/// - a fetch is currently in flight (avoid piling on a concurrent request), or
/// - [previous] is non-null and neither watermark (`loadedFrom`/`loadedTo`)
///   moved since it was observed. This covers two related cases: a fetch
///   that just completed WITHOUT moving either watermark (a permanent
///   failure or exhausted history), and a state replacement (e.g. a provider
///   rebuild) that happens to carry identical watermarks — neither is new
///   information worth acting on. Retrying automatically on either would
///   storm: the retry's own failure (or no-op) produces an identical
///   no-progress transition, which would otherwise re-trigger another retry
///   forever for as long as the screen stays parked on that month. The next
///   real trigger — a page change, pull-to-refresh, or a provider reset that
///   actually changes the watermark — gets a fresh attempt, matching the
///   backward path's non-progress guard in `_ensureMonthLoadedBackward`.
///
/// Otherwise returns `true`.
bool shouldRecoverFocusedMonth({
  required DashboardState? previous,
  required DashboardState next,
  required DateTime focusedDay,
}) {
  if (next.isLoadingOlder || next.isLoadingNewer) return false;
  if (next.coversMonth(focusedDay)) return false;

  if (previous != null &&
      next.loadedTo == previous.loadedTo &&
      next.loadedFrom == previous.loadedFrom) {
    return false;
  }

  return true;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class DashboardNotifier extends AsyncNotifier<DashboardState> {
  /// Days of past events the initial payload covers — must match the backend
  /// DashboardController::INITIAL_PAST_WINDOW_DAYS.
  static const int _initialPastWindowDays = 30;

  /// Days of future events the initial payload covers.
  static const int _initialForwardWindowDays = 90;

  /// Truncates a [DateTime] to midnight (date-only) for stable comparisons.
  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _initialTo() => _dateOnly(
      DateTime.now().add(const Duration(days: _initialForwardWindowDays)));

  static const String _cacheName = 'dashboard';

  bool get _isOffline => ref.read(connectivityProvider).value == false;

  @override
  Future<DashboardState> build() async {
    final initialFrom = _dateOnly(
      DateTime.now().subtract(const Duration(days: _initialPastWindowDays)),
    );
    final initialTo = _initialTo();

    // Wait for band selection to resolve before fetching — avoids a missing
    // X-Band-ID header on the first request when storage hasn't been read yet.
    final bandId = await ref.watch(selectedBandProvider.future);
    if (bandId == null) {
      return DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: initialFrom,
        loadedTo: initialTo,
      );
    }

    final repo = ref.watch(dashboardRepositoryProvider);
    final cache = ref.read(apiCacheStorageProvider);

    final cached = cache.read('$bandId:$_cacheName');
    if (cached != null) {
      // Instant paint from disk, then refresh in the background. Watermarks
      // are computed fresh from now — the cached events fill whatever slice
      // of the window they cover until revalidation lands.
      final parsed = DashboardRepository.parseDashboard(cached.payload);
      // Defer the background refresh until after the framework commits this
      // build's returned value — otherwise refresh's `state = …` lands first
      // and is immediately overwritten by build's own result.
      // ignore: unawaited_futures
      Future<void>(refresh);
      return DashboardState(
        events: parsed.events,
        upcomingCharts: parsed.upcomingCharts,
        loadedFrom: initialFrom,
        loadedTo: initialTo,
      );
    }

    // Cold path. Offline with nothing cached: fail fast with a friendly
    // error instead of waiting out the connect timeout.
    if (_isOffline) throw const OfflineException();
    final result = await repo.getDashboardRaw(to: _ymd(initialTo));
    cache.write('$bandId:$_cacheName', result.raw);
    return DashboardState(
      events: result.events,
      upcomingCharts: result.upcomingCharts,
      loadedFrom: initialFrom,
      loadedTo: initialTo,
    );
  }

  /// Re-fetches the dashboard from the server, in place. NEVER discards
  /// on-screen data: with data present, a failure is silent and offline skips
  /// the attempt entirely. Only from an empty/error state does it show a
  /// loading spinner (the explicit user retry path).
  Future<void> refresh() async {
    // Capture the band (and its cache key) BEFORE the fetch: if the user
    // switches bands mid-flight, we must not write band A's payload under
    // band B's key nor clobber band B's state with it.
    final bandIdAtStart = ref.read(selectedBandProvider).value;
    final keyAtStart =
        bandIdAtStart == null ? null : '$bandIdAtStart:$_cacheName';

    final hadValue = state.hasValue;
    if (!hadValue) state = const AsyncValue.loading();
    try {
      if (_isOffline) {
        if (hadValue) return; // keep data, skip the attempt
        throw const OfflineException();
      }
      final initialTo = _initialTo();
      final repo = ref.read(dashboardRepositoryProvider);
      final result = await repo.getDashboardRaw(to: _ymd(initialTo));
      if (!ref.mounted) return;
      // Abort entirely — no cache write, no state assignment — if the
      // selected band changed while the fetch was in flight. Otherwise band
      // A's payload would be written under band B's cache key and clobber
      // band B's on-screen state, persisting the poisoning across restarts.
      if (ref.read(selectedBandProvider).value != bandIdAtStart) return;
      if (keyAtStart != null) {
        ref.read(apiCacheStorageProvider).write(keyAtStart, result.raw);
      }
      state = AsyncValue.data(DashboardState(
        events: result.events,
        upcomingCharts: result.upcomingCharts,
        loadedFrom: _dateOnly(
          DateTime.now().subtract(const Duration(days: _initialPastWindowDays)),
        ),
        loadedTo: initialTo,
      ));
    } catch (e, st) {
      if (!ref.mounted) return;
      if (state.hasValue) return; // never discard on-screen data
      state = AsyncValue.error(e, st);
    }
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

      // Merge against the LATEST state, not the pre-await `current` snapshot —
      // a concurrent _loadNewer may have completed while this await was
      // pending and mutated state in the meantime. Using a stale snapshot as
      // the merge base would silently discard that concurrent update.
      final latest = state.value ?? current;

      // Dedup only among events that have an id; events without one (e.g. some
      // rehearsal/scheduled shapes) are always kept — collapsing them by a
      // shared null id would silently drop distinct events.
      final existingIds =
          latest.events.map((e) => e.id).whereType<int>().toSet();
      final merged = [
        ...latest.events,
        ...older.where((e) => e.id == null || !existingIds.contains(e.id)),
      ];

      // loadedFrom only ever moves backward: take the earlier of this fetch's
      // candidate and whatever latest.loadedFrom has become concurrently.
      final candidateLoadedFrom =
          current.loadedFrom.subtract(const Duration(days: 30));
      final nextLoadedFrom = candidateLoadedFrom.isBefore(latest.loadedFrom)
          ? candidateLoadedFrom
          : latest.loadedFrom;

      state = AsyncValue.data(latest.copyWith(
        events: merged,
        loadedFrom: nextLoadedFrom,
        isLoadingOlder: false,
        hasReachedStart: older.isEmpty,
      ));
    } catch (_) {
      state = AsyncValue.data(
        (state.value ?? current).copyWith(isLoadingOlder: false),
      );
    }
  }

  /// Fetches [loadedTo, target) and merges. [target] must be a month-start
  /// (exclusive bound). No-ops while in flight or when already covered.
  Future<void> _loadNewer(DateTime target) async {
    final current = state.value;
    if (current == null) return;
    if (current.isLoadingNewer) return;
    if (!target.isAfter(current.loadedTo)) return; // already covered

    state = AsyncValue.data(current.copyWith(isLoadingNewer: true));

    try {
      final repo = ref.read(dashboardRepositoryProvider);
      final newer = await repo.loadNewerEvents(
          _ymd(current.loadedTo), _ymd(target));

      // Merge against the LATEST state, not the pre-await `current` snapshot —
      // a concurrent loadOlder may have completed while this await was
      // pending and mutated state in the meantime. Using a stale snapshot as
      // the merge base would silently discard that concurrent update.
      final latest = state.value ?? current;

      // Dedup by id when present; by key for null-id events (virtual
      // rehearsals) so an inclusive boundary day can never duplicate.
      final existingIds =
          latest.events.map((e) => e.id).whereType<int>().toSet();
      final existingKeys = latest.events.map((e) => e.key).toSet();
      final merged = [
        ...latest.events,
        ...newer.where((e) => e.id != null
            ? !existingIds.contains(e.id)
            : !existingKeys.contains(e.key)),
      ];

      // loadedTo only ever moves forward: never move it backward even if a
      // concurrent op already advanced it further than this fetch's target.
      final nextLoadedTo =
          target.isAfter(latest.loadedTo) ? target : latest.loadedTo;

      state = AsyncValue.data(latest.copyWith(
        events: merged,
        loadedTo: nextLoadedTo,
        isLoadingNewer: false,
      ));
    } catch (_) {
      state = AsyncValue.data(
        (state.value ?? current).copyWith(isLoadingNewer: false),
      );
    }
  }

  /// Ensures the WHOLE of [focusedDay]'s month is loaded, fetching older
  /// chunks backward and/or one newer window forward as needed.
  ///
  /// Backward: fetches when the focused month's first day is strictly before
  /// the (day-granular) [DashboardState.loadedFrom] watermark — so forward
  /// navigation, or returning into a fully-loaded range, never triggers a
  /// fetch.
  ///
  /// The initial window starts mid-month (today − 30d), so the watermark's own
  /// month is only partially loaded. Comparing the month's FIRST day against the
  /// day-granular watermark means swiping into that month backfills its earlier
  /// days rather than leaving them blank. Loops to cover multi-month jumps,
  /// stopping when covered or history is exhausted.
  ///
  /// Forward: fetches the focused month's exclusive end (the first day of the
  /// NEXT month) in a single window when it is beyond [DashboardState.loadedTo]
  /// — covering multi-month forward jumps in one fetch rather than looping.
  Future<void> ensureMonthLoaded(DateTime focusedDay) async {
    await _ensureMonthLoadedBackward(
        DateTime(focusedDay.year, focusedDay.month, 1));

    // Forward: cover the focused month in ONE fetch to the month's exclusive
    // end. DateTime normalizes month 13 to January of the next year.
    final nextMonthFirst = DateTime(focusedDay.year, focusedDay.month + 1, 1);
    final current = state.value;
    if (current != null && nextMonthFirst.isAfter(current.loadedTo)) {
      await _loadNewer(nextMonthFirst);
    }
  }

  /// Backward phase of [ensureMonthLoaded]: the original while-loop body,
  /// looping [loadOlder] calls until [monthStart] is covered or history is
  /// exhausted.
  Future<void> _ensureMonthLoadedBackward(DateTime monthStart) async {
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
