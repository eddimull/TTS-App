import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_cache_storage.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_window_provider.dart';
import 'package:tts_bandmate/features/bookings/providers/clock_provider.dart';

/// Stub repository that records each call's `from`/`to` and returns
/// whatever the test programs.
class _StubRepo implements BookingsRepository {
  final List<({DateTime? from, DateTime? to})> calls = [];
  List<List<BookingSummary>> responsesQueue = [];
  int _responseIdx = 0;

  @override
  Future<({List<BookingSummary> parsed, List<Map<String, dynamic>> raw})>
      getAllUserBookingsRaw({
    String? status,
    bool upcomingOnly = false,
    int? year,
    DateTime? from,
    DateTime? to,
  }) async {
    calls.add((from: from, to: to));
    final parsed = _responseIdx >= responsesQueue.length
        ? const <BookingSummary>[]
        : responsesQueue[_responseIdx++];
    final raw = parsed
        .map((b) => {
              'id': b.id,
              'name': b.name,
              'date': b.startDate,
              'is_paid': false,
              'contacts': const [],
            })
        .toList();
    return (parsed: parsed, raw: raw);
  }

  // The other repo methods aren't used by the window provider.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Returns `firstResponse` on the first call, then `nextResponseFuture` on
/// any subsequent call — lets tests hold a fetch open mid-flight.
class _PendingRepo implements BookingsRepository {
  _PendingRepo({required this.firstResponse, required this.nextResponseFuture});

  final List<BookingSummary> firstResponse;
  final Future<List<BookingSummary>> nextResponseFuture;
  int _calls = 0;

  @override
  Future<({List<BookingSummary> parsed, List<Map<String, dynamic>> raw})>
      getAllUserBookingsRaw({
    String? status,
    bool upcomingOnly = false,
    int? year,
    DateTime? from,
    DateTime? to,
  }) async {
    _calls++;
    if (_calls == 1) {
      return (parsed: firstResponse, raw: const <Map<String, dynamic>>[]);
    }
    final next = await nextResponseFuture;
    return (parsed: next, raw: const <Map<String, dynamic>>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Returns `firstResponse` on the first call, then throws.
class _ThrowingRepo implements BookingsRepository {
  _ThrowingRepo({required this.firstResponse, required this.thrownError});

  final List<BookingSummary> firstResponse;
  final Object thrownError;
  int _calls = 0;

  @override
  Future<({List<BookingSummary> parsed, List<Map<String, dynamic>> raw})>
      getAllUserBookingsRaw({
    String? status,
    bool upcomingOnly = false,
    int? year,
    DateTime? from,
    DateTime? to,
  }) async {
    _calls++;
    if (_calls == 1) {
      return (parsed: firstResponse, raw: const <Map<String, dynamic>>[]);
    }
    throw thrownError;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AlwaysThrowRepo implements BookingsRepository {
  _AlwaysThrowRepo(this.error);
  final Object error;

  @override
  Future<({List<BookingSummary> parsed, List<Map<String, dynamic>> raw})>
      getAllUserBookingsRaw({
    String? status,
    bool upcomingOnly = false,
    int? year,
    DateTime? from,
    DateTime? to,
  }) async {
    throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Routes by the requested window: the initial-bounds call (revalidate) waits
/// on [revalidateGate] so the test can hold it open while a loadLater runs; the
/// later-bounds call (loadLater) resolves immediately with [laterResponse].
class _RaceRepo implements BookingsRepository {
  _RaceRepo({
    required this.initialFrom,
    required this.revalidateGate,
    required this.revalidateResponse,
    required this.laterResponse,
  });

  final DateTime initialFrom;
  final Future<void> revalidateGate;
  final List<BookingSummary> revalidateResponse;
  final List<BookingSummary> laterResponse;

  @override
  Future<({List<BookingSummary> parsed, List<Map<String, dynamic>> raw})>
      getAllUserBookingsRaw({
    String? status,
    bool upcomingOnly = false,
    int? year,
    DateTime? from,
    DateTime? to,
  }) async {
    if (from == initialFrom) {
      await revalidateGate; // hold the revalidation open
      return (parsed: revalidateResponse, raw: const <Map<String, dynamic>>[]);
    }
    return (parsed: laterResponse, raw: const <Map<String, dynamic>>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCacheStorage implements BookingsCacheStorage {
  BookingsWindowCache? stored;

  @override
  BookingsWindowCache? read() => stored;
  @override
  void write(BookingsWindowCache cache) => stored = cache;
  @override
  void clear() => stored = null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BookingSummary _b(int id, String date) => BookingSummary(
      id: id,
      name: 'b$id',
      startDate: date,
      endDate: date,
      eventCount: 1,
      isMultiEvent: false,
      isPaid: false,
      contacts: const [],
    );

ProviderContainer _container({
  required BookingsRepository repo,
  required DateTime now,
  BookingsCacheStorage? cache,
}) {
  return ProviderContainer(overrides: [
    bookingsRepositoryProvider.overrideWithValue(repo),
    clockProvider.overrideWithValue(() => now),
    bookingsCacheStorageProvider.overrideWithValue(cache ?? _FakeCacheStorage()),
  ]);
}

void main() {
  group('BookingsWindowNotifier.build', () {
    test('initial window is today − 3mo through today + 9mo (last day)',
        () async {
      final repo = _StubRepo()..responsesQueue = [const []];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);

      expect(repo.calls, hasLength(1));
      expect(repo.calls.first.from, DateTime(2026, 2, 1));
      expect(repo.calls.first.to, DateTime(2027, 2, 28));
    });

    test('returns sorted bookings on initial load', () async {
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(2, '2026-06-01'), _b(1, '2026-04-15')],
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      final window = await c.read(bookingsWindowProvider.future);

      expect(window.bookings.map((b) => b.id).toList(), [1, 2]);
      expect(window.from, DateTime(2026, 2, 1));
      expect(window.to, DateTime(2027, 2, 28));
      expect(window.reachedEarliest, false);
      expect(window.reachedLatest, false);
      expect(window.isLoadingEarlier, false);
      expect(window.isLoadingLater, false);
    });
  });

  group('BookingsWindowNotifier.loadEarlier', () {
    test('requests current.from − 6mo through current.from − 1 day', () async {
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(1, '2026-04-15')], // initial
          [_b(0, '2025-12-01')], // earlier
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await c.read(bookingsWindowProvider.notifier).loadEarlier();

      expect(repo.calls, hasLength(2));
      // current.from was 2026-02-01 → newFrom 2025-08-01, newTo 2026-01-31.
      expect(repo.calls[1].from, DateTime(2025, 8, 1));
      expect(repo.calls[1].to, DateTime(2026, 1, 31));
    });

    test('prepends new bookings and advances from', () async {
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(1, '2026-04-15')], // initial
          [_b(0, '2025-12-01')], // earlier
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await c.read(bookingsWindowProvider.notifier).loadEarlier();

      final window = c.read(bookingsWindowProvider).value!;
      expect(window.bookings.map((b) => b.id).toList(), [0, 1]);
      expect(window.from, DateTime(2025, 8, 1));
      expect(window.to, DateTime(2027, 2, 28));
    });

    test('empty earlier response sets reachedEarliest and leaves bookings',
        () async {
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(1, '2026-04-15')], // initial
          const [],              // earlier — empty
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await c.read(bookingsWindowProvider.notifier).loadEarlier();

      final window = c.read(bookingsWindowProvider).value!;
      expect(window.reachedEarliest, true);
      expect(window.bookings.map((b) => b.id).toList(), [1]);
      expect(window.from, DateTime(2026, 2, 1)); // unchanged
    });

    test('no-op when reachedEarliest is true', () async {
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(1, '2026-04-15')], // initial
          const [],              // first earlier — sets reachedEarliest
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await c.read(bookingsWindowProvider.notifier).loadEarlier();
      // Second loadEarlier call should NOT hit the repo.
      await c.read(bookingsWindowProvider.notifier).loadEarlier();

      expect(repo.calls, hasLength(2));
    });
  });

  group('BookingsWindowNotifier.loadLater', () {
    test('requests current.to + 1 day through current.to + 6mo', () async {
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(1, '2026-04-15')], // initial
          [_b(2, '2027-04-01')], // later
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await c.read(bookingsWindowProvider.notifier).loadLater();

      expect(repo.calls, hasLength(2));
      // current.to was 2027-02-28 → newFrom 2027-03-01, newTo 2027-08-31.
      expect(repo.calls[1].from, DateTime(2027, 3, 1));
      expect(repo.calls[1].to, DateTime(2027, 8, 31));
    });

    test('appends new bookings and advances to', () async {
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(1, '2026-04-15')],
          [_b(2, '2027-04-01')],
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await c.read(bookingsWindowProvider.notifier).loadLater();

      final window = c.read(bookingsWindowProvider).value!;
      expect(window.bookings.map((b) => b.id).toList(), [1, 2]);
      expect(window.to, DateTime(2027, 8, 31));
    });

    test('empty later response sets reachedLatest and leaves bookings',
        () async {
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(1, '2026-04-15')],
          const [],
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await c.read(bookingsWindowProvider.notifier).loadLater();

      final window = c.read(bookingsWindowProvider).value!;
      expect(window.reachedLatest, true);
      expect(window.bookings.map((b) => b.id).toList(), [1]);
      expect(window.to, DateTime(2027, 2, 28)); // unchanged
    });

    test('no-op when reachedLatest is true', () async {
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(1, '2026-04-15')],
          const [],
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await c.read(bookingsWindowProvider.notifier).loadLater();
      await c.read(bookingsWindowProvider.notifier).loadLater();

      expect(repo.calls, hasLength(2));
    });
  });

  group('BookingsWindowNotifier.refresh', () {
    test('refresh re-runs build and re-fetches the initial window',
        () async {
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(1, '2026-04-15')], // initial
          [_b(2, '2026-04-15')], // refreshed initial
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await c.read(bookingsWindowProvider.notifier).refresh();
      await c.read(bookingsWindowProvider.future);

      expect(repo.calls, hasLength(2));
      expect(repo.calls[1].from, DateTime(2026, 2, 1));
      expect(repo.calls[1].to, DateTime(2027, 2, 28));
    });
  });

  group('BookingsWindowNotifier loading flags', () {
    test('loadEarlier sets isLoadingEarlier=true while in-flight', () async {
      final completer = Completer<List<BookingSummary>>();
      final repo = _PendingRepo(
        firstResponse: [_b(1, '2026-04-15')],
        nextResponseFuture: completer.future,
      );
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      // Don't await — let it stay in-flight.
      final inFlight =
          c.read(bookingsWindowProvider.notifier).loadEarlier();

      // Allow the synchronous state-update microtask to run.
      await Future<void>.delayed(Duration.zero);
      expect(c.read(bookingsWindowProvider).value!.isLoadingEarlier, true);

      completer.complete(const []);
      await inFlight;

      expect(c.read(bookingsWindowProvider).value!.isLoadingEarlier, false);
    });

    test('loadLater sets isLoadingLater=true while in-flight', () async {
      final completer = Completer<List<BookingSummary>>();
      final repo = _PendingRepo(
        firstResponse: [_b(1, '2026-04-15')],
        nextResponseFuture: completer.future,
      );
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      final inFlight = c.read(bookingsWindowProvider.notifier).loadLater();

      await Future<void>.delayed(Duration.zero);
      expect(c.read(bookingsWindowProvider).value!.isLoadingLater, true);

      completer.complete(const []);
      await inFlight;

      expect(c.read(bookingsWindowProvider).value!.isLoadingLater, false);
    });
  });

  group('BookingsWindowNotifier error handling', () {
    test('loadLater error preserves prior window and clears loading flag',
        () async {
      final repo = _ThrowingRepo(
        firstResponse: [_b(1, '2026-04-15')],
        thrownError: Exception('boom'),
      );
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);

      // Should not throw out to the test if the implementation chose
      // copyWithPrevious; if it chose rethrow, catch here.
      try {
        await c.read(bookingsWindowProvider.notifier).loadLater();
      } catch (_) {
        // tolerated — both shapes (AsyncError-with-previous and rethrow)
        // are acceptable as long as the slice is preserved.
      }

      // The window must still be readable (slice not lost).
      final state = c.read(bookingsWindowProvider);
      final value = state.value;
      expect(value, isNotNull, reason: 'prior window should be preserved');
      expect(value!.bookings.map((b) => b.id).toList(), [1]);
      expect(value.isLoadingLater, false);
    });
  });

  group('BookingsWindowNotifier cache', () {
    BookingsWindowCache seedCache(List<BookingSummary> bookings) {
      return BookingsWindowCache(
        from: DateTime(2026, 2, 1),
        to: DateTime(2027, 2, 28),
        cachedAt: DateTime(2026, 5, 15),
        rawBookings: bookings
            .map((b) => {
                  'id': b.id,
                  'name': b.name,
                  'date': b.startDate,
                  'is_paid': false,
                  'contacts': const [],
                })
            .toList(),
      );
    }

    test('build returns cached data without awaiting the network', () async {
      final cache = _FakeCacheStorage()..stored = seedCache([_b(1, '2026-04-15')]);
      final repo = _PendingRepo(
        firstResponse: const [],
        nextResponseFuture: Completer<List<BookingSummary>>().future,
      );
      final c = _container(repo: repo, now: DateTime(2026, 5, 15), cache: cache);
      addTearDown(c.dispose);

      final window = await c.read(bookingsWindowProvider.future);
      expect(window.bookings.map((b) => b.id).toList(), [1]);
    });

    test('revalidate swaps in fresh data and rewrites the cache', () async {
      final cache = _FakeCacheStorage()..stored = seedCache([_b(1, '2026-04-15')]);
      final repo = _StubRepo()..responsesQueue = [[_b(2, '2026-04-20')]];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15), cache: cache);
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await pumpEventQueue();

      expect(c.read(bookingsWindowProvider).value!.bookings.map((b) => b.id).toList(), [2]);
      expect(cache.stored!.rawBookings.first['id'], 2);
    });

    test('revalidate error keeps cached data', () async {
      final cache = _FakeCacheStorage()..stored = seedCache([_b(1, '2026-04-15')]);
      final repo = _AlwaysThrowRepo(Exception('boom'));
      final c = _container(repo: repo, now: DateTime(2026, 5, 15), cache: cache);
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await pumpEventQueue();

      expect(c.read(bookingsWindowProvider).value!.bookings.map((b) => b.id).toList(), [1]);
    });

    test('no cache build awaits network and writes cache', () async {
      final cache = _FakeCacheStorage();
      final repo = _StubRepo()..responsesQueue = [[_b(5, '2026-05-20')]];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15), cache: cache);
      addTearDown(c.dispose);

      final window = await c.read(bookingsWindowProvider.future);
      expect(window.bookings.map((b) => b.id).toList(), [5]);
      expect(cache.stored, isNotNull);
    });

    test('refresh clears cache and re-fetches synchronously (no stale paint)',
        () async {
      // Seed a cache so the FIRST build would normally paint from disk. After
      // refresh, the cache must be cleared so build takes the cold path and the
      // re-fetched data is awaited (visible immediately, not via background
      // revalidation).
      final cache = _FakeCacheStorage()..stored = seedCache([_b(1, '2026-04-15')]);
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(9, '2026-05-20')], // the refreshed (cold-path) fetch
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15), cache: cache);
      addTearDown(c.dispose);

      // Initial cached paint.
      await c.read(bookingsWindowProvider.future);

      await c.read(bookingsWindowProvider.notifier).refresh();
      final window = await c.read(bookingsWindowProvider.future);

      // Fresh data is present synchronously after refresh completes.
      expect(window.bookings.map((b) => b.id).toList(), [9]);
      // Cache was rewritten by the cold-path build.
      expect(cache.stored!.rawBookings.first['id'], 9);
    });

    test('revalidate does not clobber a window expanded by loadLater', () async {
      // Warm paint, then the user scrolls and loadLater expands the window while
      // the background revalidation is still in flight. When revalidation lands
      // it must NOT replace the expanded window (which would drop the loaded
      // slice and snap the list back) — but it must still refresh the cache.
      final gate = Completer<void>();
      final cache = _FakeCacheStorage()..stored = seedCache([_b(1, '2026-04-15')]);
      final repo = _RaceRepo(
        initialFrom: DateTime(2026, 2, 1), // matches build's computed `from`
        revalidateGate: gate.future,
        revalidateResponse: [_b(1, '2026-04-15')], // would reset to initial-only
        laterResponse: [_b(2, '2027-04-01')], // the appended later slice
      );
      final c = _container(repo: repo, now: DateTime(2026, 5, 15), cache: cache);
      addTearDown(c.dispose);

      // Cached warm paint; revalidation starts but blocks on `gate`.
      await c.read(bookingsWindowProvider.future);
      await pumpEventQueue();

      // User scrolls to the bottom edge → loadLater expands the window.
      await c.read(bookingsWindowProvider.notifier).loadLater();
      expect(
        c.read(bookingsWindowProvider).value!.bookings.map((b) => b.id).toList(),
        [1, 2],
      );
      final expandedTo = c.read(bookingsWindowProvider).value!.to;

      // Now let the in-flight revalidation complete.
      gate.complete();
      await pumpEventQueue();

      final window = c.read(bookingsWindowProvider).value!;
      // Expanded slice preserved; bounds not reset to the initial window.
      expect(window.bookings.map((b) => b.id).toList(), [1, 2]);
      expect(window.to, expandedTo);
      // Cache still refreshed for the next cold start.
      expect(cache.stored, isNotNull);
      expect(cache.stored!.from, DateTime(2026, 2, 1));
    });
  });
}
