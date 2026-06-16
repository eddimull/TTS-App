import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bookings_cache_storage.dart';
import '../data/bookings_repository.dart';
import '../data/models/booking_summary.dart';
import 'clock_provider.dart';

/// Loaded slice of the user's bookings — what's currently in memory plus
/// the per-direction edge/loading flags that drive auto-load on scroll.
///
/// `bookings` is sorted ascending by date. `from` and `to` are inclusive.
class BookingsWindow {
  const BookingsWindow({
    required this.from,
    required this.to,
    required this.bookings,
    required this.reachedEarliest,
    required this.reachedLatest,
    required this.isLoadingEarlier,
    required this.isLoadingLater,
  });

  final DateTime from;
  final DateTime to;
  final List<BookingSummary> bookings;
  final bool reachedEarliest;
  final bool reachedLatest;
  final bool isLoadingEarlier;
  final bool isLoadingLater;

  BookingsWindow copyWith({
    DateTime? from,
    DateTime? to,
    List<BookingSummary>? bookings,
    bool? reachedEarliest,
    bool? reachedLatest,
    bool? isLoadingEarlier,
    bool? isLoadingLater,
  }) {
    return BookingsWindow(
      from: from ?? this.from,
      to: to ?? this.to,
      bookings: bookings ?? this.bookings,
      reachedEarliest: reachedEarliest ?? this.reachedEarliest,
      reachedLatest: reachedLatest ?? this.reachedLatest,
      isLoadingEarlier: isLoadingEarlier ?? this.isLoadingEarlier,
      isLoadingLater: isLoadingLater ?? this.isLoadingLater,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookingsWindow &&
          from == other.from &&
          to == other.to &&
          reachedEarliest == other.reachedEarliest &&
          reachedLatest == other.reachedLatest &&
          isLoadingEarlier == other.isLoadingEarlier &&
          isLoadingLater == other.isLoadingLater &&
          const ListEquality<BookingSummary>().equals(bookings, other.bookings);

  @override
  int get hashCode => Object.hash(
        from,
        to,
        reachedEarliest,
        reachedLatest,
        isLoadingEarlier,
        isLoadingLater,
        const ListEquality<BookingSummary>().hash(bookings),
      );
}

class BookingsWindowNotifier extends AsyncNotifier<BookingsWindow> {
  static const int _initialLookbackMonths = 3;
  static const int _initialLookaheadMonths = 9;
  static const int _expansionMonths = 6;

  @override
  Future<BookingsWindow> build() async {
    final now = ref.read(clockProvider)();
    final from = DateTime(now.year, now.month - _initialLookbackMonths, 1);
    // Last day of (now.month + lookahead): use day=0 of the next month,
    // which Dart normalizes to the last day of the previous month.
    final to = DateTime(now.year, now.month + _initialLookaheadMonths + 1, 0);

    final cache = ref.read(bookingsCacheStorageProvider);
    final cached = cache.read();

    if (cached != null) {
      // Instant paint from disk, then refresh in the background. Paint with the
      // freshly-computed [from]/[to] (not the cache's stored bounds): the cached
      // raw bookings are what matter, and using current bounds keeps the
      // loadEarlier/loadLater edge math correct during the brief window before
      // revalidation lands.
      final bookings = cached.rawBookings.map(BookingSummary.fromJson).toList();
      // Defer the background refresh until after the framework commits this
      // build's returned value — otherwise revalidate's `state = …` lands
      // first and is immediately overwritten by build's own result.
      // ignore: unawaited_futures
      Future<void>(() => _revalidate(from: from, to: to));
      return _initialWindow(from: from, to: to, bookings: bookings);
    }

    // Cold start — await the network (a blocking spinner is correct here).
    final repo = ref.read(bookingsRepositoryProvider);
    final result = await repo.getAllUserBookingsRaw(from: from, to: to);
    cache.write(BookingsWindowCache(
      from: from,
      to: to,
      cachedAt: now,
      rawBookings: result.raw,
    ));
    return _initialWindow(from: from, to: to, bookings: result.parsed);
  }

  /// Builds a fresh, un-expanded [BookingsWindow] (no edges reached, no loading
  /// in flight). Shared by the cold-start, warm-paint, and revalidate paths so
  /// the initial-window shape stays in one place.
  BookingsWindow _initialWindow({
    required DateTime from,
    required DateTime to,
    required List<BookingSummary> bookings,
  }) {
    return BookingsWindow(
      from: from,
      to: to,
      bookings: _sortAscByDate(bookings),
      reachedEarliest: false,
      reachedLatest: false,
      isLoadingEarlier: false,
      isLoadingLater: false,
    );
  }

  /// Background refresh of the canonical [from]..[to] window. Swaps fresh data
  /// into state and rewrites the cache on success; preserves cached data on
  /// error (matching loadEarlier/loadLater's "don't lose the slice" policy).
  Future<void> _revalidate({required DateTime from, required DateTime to}) async {
    try {
      final repo = ref.read(bookingsRepositoryProvider);
      final result = await repo.getAllUserBookingsRaw(from: from, to: to);
      if (!ref.mounted) return;
      ref.read(bookingsCacheStorageProvider).write(BookingsWindowCache(
            from: from,
            to: to,
            cachedAt: ref.read(clockProvider)(),
            rawBookings: result.raw,
          ));
      state = AsyncData(_initialWindow(from: from, to: to, bookings: result.parsed));
    } catch (_) {
      // Keep cached data on screen; silent.
    }
  }

  Future<void> loadEarlier() async {
    final value = state.value;
    if (value == null) return;
    if (value.isLoadingEarlier || value.reachedEarliest) return;

    state = AsyncData(value.copyWith(isLoadingEarlier: true));

    // First day of (value.from.month - expansion).
    final newFrom = DateTime(
      value.from.year,
      value.from.month - _expansionMonths,
      1,
    );
    final newTo = value.from.subtract(const Duration(days: 1));

    try {
      final repo = ref.read(bookingsRepositoryProvider);
      final fetched =
          (await repo.getAllUserBookingsRaw(from: newFrom, to: newTo)).parsed;

      if (!ref.mounted) return;
      final current = state.value!;
      if (fetched.isEmpty) {
        state = AsyncData(current.copyWith(
          reachedEarliest: true,
          isLoadingEarlier: false,
        ));
      } else {
        final merged = [..._sortAscByDate(fetched), ...current.bookings];
        state = AsyncData(current.copyWith(
          bookings: merged,
          from: newFrom,
          isLoadingEarlier: false,
        ));
      }
    } catch (_) {
      // Preserve the prior window — losing the slice on a transient blip
      // would be a UX regression. Just clear the loading flag and rethrow
      // so the caller's await sees the failure.
      final prior = state.value;
      if (prior != null) {
        state = AsyncData(prior.copyWith(isLoadingEarlier: false));
      }
      rethrow;
    }
  }

  Future<void> loadLater() async {
    final value = state.value;
    if (value == null) return;
    if (value.isLoadingLater || value.reachedLatest) return;

    state = AsyncData(value.copyWith(isLoadingLater: true));

    final newFrom = value.to.add(const Duration(days: 1));
    // Last day of (value.to.month + expansion): use day=0 of the
    // following month for end-of-month normalization.
    final newTo = DateTime(
      value.to.year,
      value.to.month + _expansionMonths + 1,
      0,
    );

    try {
      final repo = ref.read(bookingsRepositoryProvider);
      final fetched =
          (await repo.getAllUserBookingsRaw(from: newFrom, to: newTo)).parsed;

      if (!ref.mounted) return;
      final current = state.value!;
      if (fetched.isEmpty) {
        state = AsyncData(current.copyWith(
          reachedLatest: true,
          isLoadingLater: false,
        ));
      } else {
        final merged = [...current.bookings, ..._sortAscByDate(fetched)];
        state = AsyncData(current.copyWith(
          bookings: merged,
          to: newTo,
          isLoadingLater: false,
        ));
      }
    } catch (_) {
      // Preserve the prior window — losing the slice on a transient blip
      // would be a UX regression. Just clear the loading flag and rethrow
      // so the caller's await sees the failure.
      final prior = state.value;
      if (prior != null) {
        state = AsyncData(prior.copyWith(isLoadingLater: false));
      }
      rethrow;
    }
  }

  /// Re-runs `build` and waits for the new initial window to load.
  ///
  /// Clears the disk cache first so the re-run takes the cold path
  /// (synchronous network fetch + cache write) rather than painting the now
  /// stale cache and revalidating in the background. Use this where serving
  /// pre-mutation data — even briefly — would be wrong, e.g. an explicit user
  /// retry. (Booking mutations clear the cache via `CacheInvalidator` before
  /// invalidating this provider, achieving the same cold-path re-run.)
  Future<void> refresh() async {
    ref.read(bookingsCacheStorageProvider).clear();
    ref.invalidateSelf();
    await future;
  }

  static List<BookingSummary> _sortAscByDate(List<BookingSummary> input) {
    final sorted = [...input];
    sorted.sort((a, b) => a.parsedStartDate.compareTo(b.parsedStartDate));
    return sorted;
  }
}

final bookingsWindowProvider =
    AsyncNotifierProvider<BookingsWindowNotifier, BookingsWindow>(
  BookingsWindowNotifier.new,
);
