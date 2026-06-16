# Bookings Instant-Paint, Disk Cache & Silent Revalidation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Bookings screen paint instantly from a disk cache, refresh silently in the background, and open already-scrolled to the nearest-upcoming booking (no visible content shift).

**Architecture:** Add a `SharedPreferences`-backed `BookingsCacheStorage` storing the initial window's raw API JSON. `BookingsWindowNotifier.build()` returns cached data synchronously then fires a non-awaited `_revalidate()` (stale-while-revalidate). The repository surfaces raw response maps so no `toJson` is needed. The screen computes `initialScrollIndex` during build, replacing the post-frame jump apparatus.

**Tech Stack:** Flutter, Riverpod v2 (`AsyncNotifier`), `shared_preferences`, `dio`, `ScrollablePositionedList`.

Spec: `docs/superpowers/specs/2026-06-15-bookings-cache-and-position-design.md`

---

## File Structure

- **Create** `lib/features/bookings/data/bookings_cache_storage.dart` — `BookingsWindowCache` value object + `BookingsCacheStorage` prefs wrapper + `bookingsCacheStorageProvider`.
- **Modify** `lib/features/bookings/data/bookings_repository.dart` — add `getAllUserBookingsRaw`; refactor `getAllUserBookings` to delegate to it.
- **Modify** `lib/features/bookings/providers/bookings_window_provider.dart` — cache read in `build()`, `_revalidate()`, write-through.
- **Modify** `lib/features/bookings/screens/bookings_screen.dart` — `initialScrollIndex`; delete jump apparatus.
- **Modify** `lib/main.dart` — resolve `bookingsCacheStorageProvider`.
- **Modify** `lib/features/auth/providers/auth_provider.dart` — clear cache on logout.
- **Create/Modify** tests under `test/features/bookings/...`.

Tasks are ordered so each leaves the build green. Repo change (Task 1) lands first because the notifier depends on it.

---

## Task 1: Repository surfaces raw booking maps

**Files:**
- Modify: `lib/features/bookings/data/bookings_repository.dart:58-83`
- Test: `test/features/bookings/bookings_repository_user_bookings_test.dart`

- [ ] **Step 1: Write the failing test**

Add to the existing `group('BookingsRepository.getAllUserBookings', ...)` in `test/features/bookings/bookings_repository_user_bookings_test.dart` (the file already has `_StubAdapter` and `_json` helpers; construct the repo the same way the existing tests do):

```dart
test('getAllUserBookingsRaw returns parsed models and raw maps', () async {
  final adapter = _StubAdapter((req) async {
    return _json(200, {
      'bookings': [
        {
          'id': 7,
          'name': 'Gala',
          'date': '2026-07-01',
          'is_paid': false,
          'contacts': [],
        },
      ],
    });
  });
  final dio = Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = adapter;
  final repo = BookingsRepository(dio);

  final result = await repo.getAllUserBookingsRaw();

  expect(result.parsed.map((b) => b.id).toList(), [7]);
  expect(result.raw, hasLength(1));
  expect(result.raw.first['id'], 7);
  expect(result.raw.first['name'], 'Gala');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/bookings/bookings_repository_user_bookings_test.dart`
Expected: FAIL — `The method 'getAllUserBookingsRaw' isn't defined`.

- [ ] **Step 3: Implement raw method and delegate**

In `lib/features/bookings/data/bookings_repository.dart`, replace the existing `getAllUserBookings` body (lines 58-83) with a delegating implementation and add the raw variant:

```dart
  /// Like [getAllUserBookings] but also returns the raw JSON maps from the
  /// response, so callers can persist them verbatim (the summary models have
  /// no `toJson`). `raw[i]` corresponds to `parsed[i]`.
  Future<({List<BookingSummary> parsed, List<Map<String, dynamic>> raw})>
      getAllUserBookingsRaw({
    String? status,
    bool upcomingOnly = false,
    int? year,
    DateTime? from,
    DateTime? to,
  }) async {
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (upcomingOnly) queryParams['upcoming'] = '1';
    if (year != null) queryParams['year'] = year.toString();
    if (from != null) queryParams['from'] = _formatDate(from);
    if (to != null) queryParams['to'] = _formatDate(to);

    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileMeBookings,
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    final data = response.data!;
    final raw = (data['bookings'] as List<dynamic>).cast<Map<String, dynamic>>();
    final parsed = raw.map(BookingSummary.fromJson).toList();
    return (parsed: parsed, raw: raw);
  }

  Future<List<BookingSummary>> getAllUserBookings({
    String? status,
    bool upcomingOnly = false,
    int? year,
    DateTime? from,
    DateTime? to,
  }) async {
    final result = await getAllUserBookingsRaw(
      status: status,
      upcomingOnly: upcomingOnly,
      year: year,
      from: from,
      to: to,
    );
    return result.parsed;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/bookings/bookings_repository_user_bookings_test.dart`
Expected: PASS (all tests in file, including the pre-existing ones).

- [ ] **Step 5: Commit**

```bash
git add lib/features/bookings/data/bookings_repository.dart test/features/bookings/bookings_repository_user_bookings_test.dart
git commit -m "feat(bookings): repository surfaces raw booking maps for caching

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `BookingsCacheStorage` + `BookingsWindowCache`

**Files:**
- Create: `lib/features/bookings/data/bookings_cache_storage.dart`
- Test: `test/features/bookings/data/bookings_cache_storage_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/bookings/data/bookings_cache_storage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_cache_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<BookingsCacheStorage> build() async {
    final prefs = await SharedPreferences.getInstance();
    return BookingsCacheStorage(prefs);
  }

  test('read returns null when nothing stored', () async {
    final storage = await build();
    expect(storage.read(), isNull);
  });

  test('write then read round-trips the cache', () async {
    final storage = await build();
    final cache = BookingsWindowCache(
      from: DateTime(2026, 2, 1),
      to: DateTime(2027, 2, 28),
      cachedAt: DateTime(2026, 5, 15, 9),
      rawBookings: [
        {'id': 1, 'name': 'Gala', 'date': '2026-06-01'},
      ],
    );
    storage.write(cache);

    final read = storage.read()!;
    expect(read.from, DateTime(2026, 2, 1));
    expect(read.to, DateTime(2027, 2, 28));
    expect(read.cachedAt, DateTime(2026, 5, 15, 9));
    expect(read.rawBookings, hasLength(1));
    expect(read.rawBookings.first['id'], 1);
    expect(read.rawBookings.first['name'], 'Gala');
  });

  test('read returns null and clears key on malformed JSON', () async {
    SharedPreferences.setMockInitialValues({
      'bookings_window_cache': 'not json{{',
    });
    final storage = await build();
    expect(storage.read(), isNull);
    // Key cleared so we don't keep re-failing.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bookings_window_cache'), isNull);
  });

  test('clear removes the cache', () async {
    final storage = await build();
    storage.write(BookingsWindowCache(
      from: DateTime(2026, 2, 1),
      to: DateTime(2027, 2, 28),
      cachedAt: DateTime(2026, 5, 15),
      rawBookings: const [],
    ));
    storage.clear();
    expect(storage.read(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/bookings/data/bookings_cache_storage_test.dart`
Expected: FAIL — target of URI doesn't exist (`bookings_cache_storage.dart`).

- [ ] **Step 3: Implement the storage**

Create `lib/features/bookings/data/bookings_cache_storage.dart`:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serializable snapshot of the initial bookings window. Stores raw API JSON
/// maps (the summary models have no `toJson`) so cached data goes back through
/// the same `BookingSummary.fromJson` path as a live response.
class BookingsWindowCache {
  const BookingsWindowCache({
    required this.from,
    required this.to,
    required this.cachedAt,
    required this.rawBookings,
  });

  final DateTime from;
  final DateTime to;
  final DateTime cachedAt;
  final List<Map<String, dynamic>> rawBookings;

  Map<String, dynamic> toJson() => {
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
        'cachedAt': cachedAt.millisecondsSinceEpoch,
        'bookings': rawBookings,
      };

  factory BookingsWindowCache.fromJson(Map<String, dynamic> json) {
    return BookingsWindowCache(
      from: DateTime.fromMillisecondsSinceEpoch((json['from'] as num).toInt()),
      to: DateTime.fromMillisecondsSinceEpoch((json['to'] as num).toInt()),
      cachedAt:
          DateTime.fromMillisecondsSinceEpoch((json['cachedAt'] as num).toInt()),
      rawBookings: (json['bookings'] as List<dynamic>)
          .cast<Map<String, dynamic>>(),
    );
  }
}

/// `SharedPreferences`-backed store for the initial bookings window. Mirrors
/// `RouteStorage`. Only the initial 3-back/9-ahead window is persisted;
/// loadEarlier/loadLater slices are not.
class BookingsCacheStorage {
  BookingsCacheStorage(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'bookings_window_cache';

  /// Returns the cached window, or null if absent or unparseable. A malformed
  /// blob is cleared so subsequent reads don't keep failing.
  BookingsWindowCache? read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return BookingsWindowCache.fromJson(decoded);
    } catch (_) {
      _prefs.remove(_key);
      return null;
    }
  }

  void write(BookingsWindowCache cache) {
    _prefs.setString(_key, jsonEncode(cache.toJson()));
  }

  void clear() {
    _prefs.remove(_key);
  }
}

/// Resolved at startup in `main.dart` (mirrors `routeStorageProvider`). The
/// async default is overridden with a pre-resolved instance so synchronous
/// `read()` works inside the window provider's `build()`.
final bookingsCacheStorageProvider = Provider<BookingsCacheStorage>((ref) {
  throw UnimplementedError(
    'bookingsCacheStorageProvider must be overridden in main()',
  );
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/bookings/data/bookings_cache_storage_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/bookings/data/bookings_cache_storage.dart test/features/bookings/data/bookings_cache_storage_test.dart
git commit -m "feat(bookings): add BookingsCacheStorage for the window snapshot

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Wire `bookingsCacheStorageProvider` in `main.dart`

**Files:**
- Modify: `lib/main.dart:71-107`

This task has no unit test (it's app wiring); correctness is verified by `flutter analyze` plus the provider tests in later tasks (which override the provider directly). The override must be present so the app doesn't throw the `UnimplementedError` at runtime.

- [ ] **Step 1: Add the override**

In `lib/main.dart`, near where `prefs` is resolved (line ~74) and `routeStorage` is built, construct the cache storage and add its override to the `ProviderScope` overrides list (alongside `routeStorageProvider.overrideWith(...)` at line ~106):

```dart
// after: final prefs = await SharedPreferences.getInstance();
final bookingsCacheStorage = BookingsCacheStorage(prefs);
```

```dart
// inside the overrides: [...] list, next to routeStorageProvider:
bookingsCacheStorageProvider.overrideWithValue(bookingsCacheStorage),
```

Add the import at the top of `main.dart`:

```dart
import 'package:tts_bandmate/features/bookings/data/bookings_cache_storage.dart';
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/main.dart`
Expected: No errors (`No issues found!` or only pre-existing unrelated infos).

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat(bookings): resolve BookingsCacheStorage at startup

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Notifier reads cache, paints instantly, revalidates

**Files:**
- Modify: `lib/features/bookings/providers/bookings_window_provider.dart:75-100`
- Test: `test/features/bookings/providers/bookings_window_provider_test.dart`

The existing test fakes implement `getAllUserBookings`. The notifier will now call `getAllUserBookingsRaw`, so the fakes must override that instead. We update them once and add cache-behavior tests.

- [ ] **Step 1: Update existing fakes to override `getAllUserBookingsRaw`**

In `test/features/bookings/providers/bookings_window_provider_test.dart`, change each fake (`_StubRepo`, `_PendingRepo`, `_ThrowingRepo`) so it overrides `getAllUserBookingsRaw` instead of `getAllUserBookings`. The notifier only calls the raw variant; returning empty `raw` is fine for tests that assert on parsed ids.

For `_StubRepo`, replace its `getAllUserBookings` override with:

```dart
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
    final parsed =
        _responseIdx >= responsesQueue.length ? const <BookingSummary>[] : responsesQueue[_responseIdx++];
    return (parsed: parsed, raw: const []);
  }
```

For `_PendingRepo`:

```dart
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
    if (_calls == 1) return (parsed: firstResponse, raw: const []);
    final next = await nextResponseFuture;
    return (parsed: next, raw: const []);
  }
```

For `_ThrowingRepo`:

```dart
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
    if (_calls == 1) return (parsed: firstResponse, raw: const []);
    throw thrownError;
  }
```

The `_container` helper must now also override `bookingsCacheStorageProvider`. Add a fake cache (in-memory, no disk) and inject it. Add near the top of the file:

```dart
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
```

Update `_container` to accept and override the cache:

```dart
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
```

Add imports at the top of the test file:

```dart
import 'package:tts_bandmate/features/bookings/data/bookings_cache_storage.dart';
```

- [ ] **Step 2: Run existing tests to confirm they still pass after the fake swap**

Run: `flutter test test/features/bookings/providers/bookings_window_provider_test.dart`
Expected: FAIL initially only if the notifier hasn't been updated yet (it still calls `getAllUserBookings`). That's expected — proceed to Step 3. (If they pass because the notifier delegates, even better.)

- [ ] **Step 3: Write the new cache-behavior failing tests**

Add a new group to the same test file:

```dart
  group('BookingsWindowNotifier cache', () {
    BookingsWindowCache _seedCache(List<BookingSummary> bookings) {
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
      final cache = _FakeCacheStorage()..stored = _seedCache([_b(1, '2026-04-15')]);
      // Repo whose fetch never completes — if build awaited it, this hangs.
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
      final cache = _FakeCacheStorage()..stored = _seedCache([_b(1, '2026-04-15')]);
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(2, '2026-04-20')], // revalidation result
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15), cache: cache);
      addTearDown(c.dispose);

      // Cached paint first.
      await c.read(bookingsWindowProvider.future);
      // Let the non-awaited _revalidate() microtasks settle.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(c.read(bookingsWindowProvider).value!.bookings.map((b) => b.id).toList(), [2]);
      expect(cache.stored!.rawBookings.first['id'], 2);
    });

    test('revalidate error keeps cached data', () async {
      final cache = _FakeCacheStorage()..stored = _seedCache([_b(1, '2026-04-15')]);
      final repo = _ThrowingRepo(
        firstResponse: const [],
        thrownError: Exception('boom'),
      );
      // _ThrowingRepo throws on the SECOND call; the first (build path) is
      // skipped because cache is present, so make it throw on first call.
      // Use a repo that always throws for revalidation:
      final throwingAlways = _AlwaysThrowRepo(Exception('boom'));
      final c = _container(repo: throwingAlways, now: DateTime(2026, 5, 15), cache: cache);
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Still the cached value; no thrown error escaped.
      expect(c.read(bookingsWindowProvider).value!.bookings.map((b) => b.id).toList(), [1]);
    });

    test('no cache → build awaits network and writes cache', () async {
      final cache = _FakeCacheStorage();
      final repo = _StubRepo()..responsesQueue = [[_b(5, '2026-05-20')]];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15), cache: cache);
      addTearDown(c.dispose);

      final window = await c.read(bookingsWindowProvider.future);
      expect(window.bookings.map((b) => b.id).toList(), [5]);
      // _StubRepo returns empty raw, so cache rawBookings is empty but present.
      expect(cache.stored, isNotNull);
    });
  });
```

Add the always-throwing fake near the other fakes:

```dart
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
```

> Note: in the `_seedCache`-based "no cache → write" test, `_StubRepo` returns
> empty `raw`, so the written cache's `rawBookings` is empty. We only assert the
> cache object exists. The "revalidate swaps + rewrites" test asserts on ids by
> seeding `raw` through the fetch path — to make that pass, `_StubRepo` must
> echo a non-empty `raw`. Update `_StubRepo.getAllUserBookingsRaw` to derive
> raw from the parsed list:
>
> ```dart
>     final raw = parsed
>         .map((b) => {'id': b.id, 'name': b.name, 'date': b.startDate, 'is_paid': false, 'contacts': const []})
>         .toList();
>     return (parsed: parsed, raw: raw);
> ```

- [ ] **Step 4: Run tests to verify they fail**

Run: `flutter test test/features/bookings/providers/bookings_window_provider_test.dart`
Expected: FAIL — `build` still calls `getAllUserBookings` and ignores the cache; revalidation method doesn't exist.

- [ ] **Step 5: Implement cache + revalidate in the notifier**

In `lib/features/bookings/providers/bookings_window_provider.dart`, replace `build()` (lines 80-100) and add helpers. Add imports for `bookings_cache_storage.dart` and `BookingSummary.fromJson` is already available via the model import:

```dart
  @override
  Future<BookingsWindow> build() async {
    final now = ref.read(clockProvider)();
    final from = DateTime(now.year, now.month - _initialLookbackMonths, 1);
    final to = DateTime(now.year, now.month + _initialLookaheadMonths + 1, 0);

    final cache = ref.read(bookingsCacheStorageProvider);
    final cached = cache.read();

    if (cached != null) {
      // Instant paint from disk, then refresh in the background.
      final bookings = cached.rawBookings.map(BookingSummary.fromJson).toList();
      // ignore: unawaited_futures
      _revalidate(from: from, to: to);
      return BookingsWindow(
        from: cached.from,
        to: cached.to,
        bookings: _sortAscByDate(bookings),
        reachedEarliest: false,
        reachedLatest: false,
        isLoadingEarlier: false,
        isLoadingLater: false,
      );
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
    return BookingsWindow(
      from: from,
      to: to,
      bookings: _sortAscByDate(result.parsed),
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
      state = AsyncData(BookingsWindow(
        from: from,
        to: to,
        bookings: _sortAscByDate(result.parsed),
        reachedEarliest: false,
        reachedLatest: false,
        isLoadingEarlier: false,
        isLoadingLater: false,
      ));
    } catch (_) {
      // Keep cached data on screen; silent.
    }
  }
```

Add the import near the top of the file:

```dart
import 'bookings_cache_storage.dart';
```

- [ ] **Step 6: Run all window-provider tests**

Run: `flutter test test/features/bookings/providers/bookings_window_provider_test.dart`
Expected: PASS (new cache group + all pre-existing loadEarlier/loadLater/refresh/flags/error tests).

- [ ] **Step 7: Commit**

```bash
git add lib/features/bookings/providers/bookings_window_provider.dart test/features/bookings/providers/bookings_window_provider_test.dart
git commit -m "feat(bookings): paint window from disk cache, revalidate in background

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Clear cache on logout

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart:137-160`
- Test: `test/auth_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/auth_provider_test.dart` a test that logout clears the bookings cache. Mirror the existing logout-test setup in that file (it already overrides `secureStorageProvider` etc.); override `bookingsCacheStorageProvider` with a fake that records `clear()`:

```dart
test('logout clears the bookings disk cache', () async {
  final cache = _RecordingCache();
  // Build the container the same way the other logout tests in this file do,
  // adding: bookingsCacheStorageProvider.overrideWithValue(cache)
  // ... (construct container, authenticate, then:)
  await container.read(authProvider.notifier).logout();
  expect(cache.cleared, isTrue);
});
```

With a fake near the top of the test file:

```dart
class _RecordingCache implements BookingsCacheStorage {
  bool cleared = false;
  @override
  void clear() => cleared = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

Import: `import 'package:tts_bandmate/features/bookings/data/bookings_cache_storage.dart';`

> If `test/auth_provider_test.dart` builds its container without a
> `bookingsCacheStorageProvider` override elsewhere, add the override only in
> this new test's container so other tests are unaffected.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/auth_provider_test.dart`
Expected: FAIL — `cache.cleared` is false (logout doesn't touch the cache yet).

- [ ] **Step 3: Implement cache clear in logout**

In `lib/features/auth/providers/auth_provider.dart`, inside `logout()`, after the `routeStorage.clearLastRoute()` best-effort block (around line 157) and before `state = const AsyncValue.data(AuthUnauthenticated());`, add:

```dart
    // Drop the bookings disk cache so a different user never sees the
    // previous user's bookings.
    try {
      ref.read(bookingsCacheStorageProvider).clear();
    } catch (_) {}
```

Add the import:

```dart
import '../../bookings/data/bookings_cache_storage.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/auth_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/providers/auth_provider.dart test/auth_provider_test.dart
git commit -m "feat(auth): clear bookings disk cache on logout

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Render already-positioned (`initialScrollIndex`), delete jump apparatus

**Files:**
- Modify: `lib/features/bookings/screens/bookings_screen.dart`
- Test: `test/features/bookings/screens/bookings_initial_position_test.dart` (new, pure-function test of the index helper)

To keep this testable without a full widget pump, extract the index computation into a pure top-level function and unit-test it; the screen calls it.

- [ ] **Step 1: Write the failing test for the index helper**

Create `test/features/bookings/screens/bookings_initial_position_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';
import 'package:tts_bandmate/features/bookings/screens/bookings_initial_position.dart';

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

void main() {
  group('initialBookingScrollIndex', () {
    test('returns header index of the nearest-upcoming booking', () {
      // Sorted asc: Apr (past), Jun (upcoming), Jul (upcoming).
      final sorted = [_b(1, '2026-04-15'), _b(2, '2026-06-10'), _b(3, '2026-07-01')];
      // monthHeaderIndex from a layout where each month has its own header:
      // items: [H apr(0), c1(1), H jun(2), c2(3), H jul(4), c3(5)]
      final monthHeaderIndex = {'2026-04': 0, '2026-06': 2, '2026-07': 4};
      final now = DateTime(2026, 5, 15);

      final idx = initialBookingScrollIndex(
        sortedFiltered: sorted,
        monthHeaderIndex: monthHeaderIndex,
        now: now,
      );
      expect(idx, 2); // header of June (nearest upcoming)
    });

    test('returns last header index when nothing is upcoming', () {
      final sorted = [_b(1, '2026-01-15'), _b(2, '2026-02-10')];
      final monthHeaderIndex = {'2026-01': 0, '2026-02': 2};
      final now = DateTime(2026, 5, 15);

      final idx = initialBookingScrollIndex(
        sortedFiltered: sorted,
        monthHeaderIndex: monthHeaderIndex,
        now: now,
      );
      expect(idx, 2); // last header (Feb)
    });

    test('returns 0 for an empty list', () {
      final idx = initialBookingScrollIndex(
        sortedFiltered: const [],
        monthHeaderIndex: const {},
        now: DateTime(2026, 5, 15),
      );
      expect(idx, 0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/bookings/screens/bookings_initial_position_test.dart`
Expected: FAIL — target URI `bookings_initial_position.dart` doesn't exist.

- [ ] **Step 3: Implement the pure helper**

Create `lib/features/bookings/screens/bookings_initial_position.dart`:

```dart
import '../data/models/booking_summary.dart';
import '../utils/booking_month_strip.dart' show findNearestUpcomingIndex, monthKeyFor;

/// Index into the rendered items list (headers + cards) that the bookings
/// list should be initially scrolled to: the month header of the
/// nearest-upcoming booking. Falls back to the last header when nothing is
/// upcoming, and 0 when the list is empty.
///
/// Caller adds any top-sentinel offset (loadEarlier spinner) separately.
int initialBookingScrollIndex({
  required List<BookingSummary> sortedFiltered,
  required Map<String, int> monthHeaderIndex,
  required DateTime now,
}) {
  if (sortedFiltered.isEmpty || monthHeaderIndex.isEmpty) return 0;

  final nearestIdx = findNearestUpcomingIndex(sortedFiltered, now);
  if (nearestIdx != null) {
    final key = monthKeyFor(sortedFiltered[nearestIdx].parsedStartDate);
    final headerIdx = monthHeaderIndex[key];
    if (headerIdx != null) return headerIdx;
  }
  // Nothing upcoming (or its header is missing): land on the last header.
  return monthHeaderIndex.values.reduce((a, b) => a > b ? a : b);
}
```

> Confirmed: `booking_month_strip.dart` exports both `findNearestUpcomingIndex`
> and `monthKeyFor` (verified against the file). The `show` clause is correct.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/bookings/screens/bookings_initial_position_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire the helper into the screen and delete the jump apparatus**

In `lib/features/bookings/screens/bookings_screen.dart`:

1. Add import: `import 'bookings_initial_position.dart';` and the `clock_provider` import if not present (`import '../providers/clock_provider.dart';`).

2. Delete these fields (lines ~64-68): `_hasJumpedToNearest`, `_jumpInFlight`, `_jumpGeneration`, `_pendingJumpRetries`, `_maxJumpRetries`.

3. Delete these methods entirely: `_scheduleJumpToNearest`, `_cancelInFlightJump`, `_attemptJump` (lines ~295-370).

4. In `build()`, delete the `ref.listen<BookingsFilterState>(...)` block (lines ~464-471) that called `_scheduleJumpToNearest`.

5. In the `data:` builder, delete the `if (!_hasJumpedToNearest) { _scheduleJumpToNearest(...); }` block (lines ~507-509).

6. Compute the initial index just before building `_buildContent`, and seed the chip key. In `_buildContent`, where `ScrollablePositionedList.builder(...)` is constructed (line ~629), add `initialScrollIndex`:

```dart
// In _buildContent, before the ScrollablePositionedList:
final initialIndex = initialBookingScrollIndex(
      sortedFiltered: data.visibleAfterFilter,
      monthHeaderIndex: data.monthHeaderIndex,
      now: ref.read(clockProvider)(),
    ) +
    (window.isLoadingEarlier ? 1 : 0);
```

```dart
ScrollablePositionedList.builder(
  itemCount: data.items.length +
      (window.isLoadingEarlier ? 1 : 0) +
      (window.isLoadingLater ? 1 : 0),
  initialScrollIndex: initialIndex,
  itemScrollController: _itemScrollController,
  itemPositionsListener: _itemPositionsListener,
  itemBuilder: (context, index) { /* unchanged */ },
),
```

7. Seed `_selectedMonthKey` so the chip highlight matches on first paint. In the `data:` builder, after `_currentItems`/`_renderedItemCount` are assigned and before returning the `Column`, add:

```dart
_selectedMonthKey ??= _monthKeyForIndex(
  initialBookingScrollIndex(
    sortedFiltered: data.visibleAfterFilter,
    monthHeaderIndex: data.monthHeaderIndex,
    now: ref.read(clockProvider)(),
  ),
);
```

where `_monthKeyForIndex` is a small private method that inverts `_monthHeaderIndex`:

```dart
String? _monthKeyForIndex(int headerIndex) {
  for (final e in _monthHeaderIndex.entries) {
    if (e.value == headerIndex) return e.key;
  }
  return null;
}
```

8. **Filter-change re-anchor:** `initialScrollIndex` only applies on first attach, so a filter change must force a fresh `ScrollablePositionedList`. Add a `key` derived from the active filter to the list so Flutter rebuilds it on filter change:

```dart
ScrollablePositionedList.builder(
  key: ValueKey('bookings-list-${filter.status}-${filter.hiddenBandIds.join(",")}'),
  // ...
)
```

Also reset `_selectedMonthKey` on filter change so the seed recomputes. Replace the deleted `ref.listen` block with a minimal one:

```dart
ref.listen<BookingsFilterState>(bookingsFilterProvider, (_, __) {
  setState(() => _selectedMonthKey = null);
});
```

> `filter` is already available in `_buildContent`'s signature. Confirmed:
> `BookingsFilterState` has `status` (a `BookingStatus` enum) and `hiddenBandIds`
> (a `Set<int>`). The key string interpolation is valid as written.

- [ ] **Step 6: Static analysis + existing screen tests**

Run: `flutter analyze lib/features/bookings/screens/bookings_screen.dart`
Expected: No errors. (Watch for "unused field/method" — those mean a jump-apparatus remnant wasn't deleted; remove it.)

Run: `flutter test test/features/bookings/bookings_screen_multi_band_test.dart`
Expected: PASS (no regression in the existing screen widget test).

- [ ] **Step 7: Commit**

```bash
git add lib/features/bookings/screens/bookings_screen.dart lib/features/bookings/screens/bookings_initial_position.dart test/features/bookings/screens/bookings_initial_position_test.dart
git commit -m "fix(bookings): render list already positioned at nearest-upcoming

Replaces the post-frame jump-to-nearest (which caused a visible shift from
the oldest booking) with ScrollablePositionedList.initialScrollIndex computed
during build. Deletes the jump/retry apparatus.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Full verification

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: All pass.

- [ ] **Step 2: Static analysis**

Run: `flutter analyze`
Expected: `No issues found!` (or only pre-existing infos unrelated to this change).

- [ ] **Step 3: Manual smoke (optional but recommended)**

Run the app (`flutter run -d <device>`), open Bookings:
- First ever open: spinner → list, already scrolled to nearest-upcoming (no shift).
- Leave tab and return: instant paint from cache, no full spinner; list silently refreshes.
- Cold restart: instant paint from disk; refreshes.
- Logout/login as another user: previous user's bookings not shown.

- [ ] **Step 4: Final commit (if any cleanup)**

```bash
git add -A
git commit -m "chore(bookings): verification cleanup

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** Fix 1 → Task 6. Fix 2 (disk cache) → Tasks 2, 3, 4. Fix 3 (revalidate) → Task 4. Logout security → Task 5. Raw-JSON serialization → Task 1. All spec sections mapped.
- **Type consistency:** `getAllUserBookingsRaw` returns `({List<BookingSummary> parsed, List<Map<String, dynamic>> raw})` everywhere (repo, fakes). `BookingsWindowCache` fields (`from`/`to`/`cachedAt`/`rawBookings`) consistent across storage, notifier, tests. `initialBookingScrollIndex` signature identical in helper and call sites.
- **Pre-verified against the codebase:** `booking_month_strip.dart` exports `findNearestUpcomingIndex` + `monthKeyFor` (Task 6); `BookingsFilterState` fields are `status` (`BookingStatus`) + `hiddenBandIds` (`Set<int>`) (Task 6).
- **One point left for the implementer:** whether `auth_provider_test.dart`'s existing container build needs the `bookingsCacheStorageProvider` override added globally vs. only in the new test (Task 5 Step 1) — depends on that file's shared setup; add the override only where needed to avoid disturbing other tests.
