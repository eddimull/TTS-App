# Bookings Windowed Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current "fetch all bookings" behavior with a windowed loader that initial-loads a 12-month slice (3mo back, 9mo forward) and auto-loads 6-month chunks on scroll edge, so bands with thousands of bookings have a fast startup.

**Architecture:** Backend gains optional `from`/`to` date-range params on `GET /api/mobile/me/bookings`. Client repository forwards them. A new `bookingsWindowProvider` (Riverpod `AsyncNotifier`) owns the loaded `BookingsWindow` (date range + bookings + edge/loading flags) and exposes `loadEarlier()` / `loadLater()`. The screen consumes the window provider, drives `loadEarlier`/`loadLater` from `_onItemPositionsChange` when within 10 items of either edge, and anchors scroll position on prepend so the user's view stays put.

**Tech Stack:** Laravel (API), Flutter / Cupertino, Riverpod v2 (`AsyncNotifier`), `scrollable_positioned_list`, intl.

**Spec:** `docs/superpowers/specs/2026-05-03-bookings-windowed-loading-design.md`

**Branch policy:** Continue on the existing `feature/bookings-styling` branch as a follow-up commit set.

---

## File Structure

**Backend (Laravel — `/home/eddie/github/TTS/`):**
- Modify: `app/Http/Controllers/Api/Mobile/BookingsController.php` — `indexForUser` validates and applies `from` / `to`.
- Modify: `tests/Feature/Api/Mobile/MeBookingsTest.php` — add 5 tests for the new param surface.

**Client (Flutter — `/home/eddie/github/tts_bandmate/`):**
- Modify: `lib/features/bookings/data/bookings_repository.dart` — `getAllUserBookings` gains `from` / `to` params.
- Modify: `test/features/bookings/bookings_repository_user_bookings_test.dart` — assertions for new query-param emission.
- Create: `lib/features/bookings/providers/clock_provider.dart` — tiny `Provider<DateTime Function()>` for deterministic test "now".
- Create: `lib/features/bookings/providers/bookings_window_provider.dart` — `BookingsWindow` value class, `BookingsWindowNotifier`, `bookingsWindowProvider`.
- Create: `test/features/bookings/providers/bookings_window_provider_test.dart` — the full unit test suite for the window notifier.
- Modify: `lib/features/bookings/providers/bookings_provider.dart` — remove the `userBookingsProvider` declaration (replaced by `bookingsWindowProvider`).
- Modify: `lib/features/bookings/screens/bookings_screen.dart` — switch from `userBookingsProvider` to `bookingsWindowProvider`, add edge-detection in `_onItemPositionsChange`, add scroll anchor on `loadEarlier`, add sentinel-spinner rows for in-flight loads, plumb sentinel-index translation through chip-highlight + jump-to-month math.

---

## Task 1: Backend — add `from`/`to` to `indexForUser`

**Files:**
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/BookingsController.php` (the `indexForUser` method, around line 67)
- Modify: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/MeBookingsTest.php` — add 5 new tests

- [ ] **Step 1: Read the existing `indexForUser` and `MeBookingsTest` to understand the patterns**

Run:
```bash
sed -n '60,100p' /home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/BookingsController.php
```
Expect: see the existing query-builder pattern with `status`, `upcoming`, `year` filters.

Run:
```bash
head -100 /home/eddie/github/TTS/tests/Feature/Api/Mobile/MeBookingsTest.php
```
Expect: see the existing test setup pattern (User factory, Bands::create, BandOwners attach, getJson assertions).

- [ ] **Step 2: Write the 5 new failing tests**

Append to `/home/eddie/github/TTS/tests/Feature/Api/Mobile/MeBookingsTest.php` (before the closing `}` of the class):

```php

    public function test_from_param_filters_to_on_or_after(): void
    {
        $user = User::factory()->create();
        $band = Bands::create([
            'name' => 'Band', 'site_name' => 'b-' . uniqid(), 'is_personal' => false,
        ]);
        BandOwners::create(['user_id' => $user->id, 'band_id' => $band->id]);

        Bookings::factory()->for($band, 'band')->create(['date' => '2026-01-15', 'name' => 'Old']);
        Bookings::factory()->for($band, 'band')->create(['date' => '2026-06-01', 'name' => 'New']);

        $response = $this->actingAs($user)
            ->getJson('/api/mobile/me/bookings?from=2026-05-01');

        $response->assertOk();
        $names = collect($response->json('bookings'))->pluck('name')->all();
        $this->assertEqualsCanonicalizing(['New'], $names);
    }

    public function test_to_param_filters_to_on_or_before(): void
    {
        $user = User::factory()->create();
        $band = Bands::create([
            'name' => 'Band', 'site_name' => 'b-' . uniqid(), 'is_personal' => false,
        ]);
        BandOwners::create(['user_id' => $user->id, 'band_id' => $band->id]);

        Bookings::factory()->for($band, 'band')->create(['date' => '2026-01-15', 'name' => 'Old']);
        Bookings::factory()->for($band, 'band')->create(['date' => '2026-06-01', 'name' => 'New']);

        $response = $this->actingAs($user)
            ->getJson('/api/mobile/me/bookings?to=2026-05-01');

        $response->assertOk();
        $names = collect($response->json('bookings'))->pluck('name')->all();
        $this->assertEqualsCanonicalizing(['Old'], $names);
    }

    public function test_from_and_to_together_narrow_to_inclusive_range(): void
    {
        $user = User::factory()->create();
        $band = Bands::create([
            'name' => 'Band', 'site_name' => 'b-' . uniqid(), 'is_personal' => false,
        ]);
        BandOwners::create(['user_id' => $user->id, 'band_id' => $band->id]);

        Bookings::factory()->for($band, 'band')->create(['date' => '2026-01-01', 'name' => 'Before']);
        Bookings::factory()->for($band, 'band')->create(['date' => '2026-03-15', 'name' => 'Inside']);
        Bookings::factory()->for($band, 'band')->create(['date' => '2026-12-01', 'name' => 'After']);

        $response = $this->actingAs($user)
            ->getJson('/api/mobile/me/bookings?from=2026-02-01&to=2026-05-01');

        $response->assertOk();
        $names = collect($response->json('bookings'))->pluck('name')->all();
        $this->assertEqualsCanonicalizing(['Inside'], $names);
    }

    public function test_from_after_to_returns_422(): void
    {
        $user = User::factory()->create();

        $response = $this->actingAs($user)
            ->getJson('/api/mobile/me/bookings?from=2026-06-01&to=2026-05-01');

        $response->assertStatus(422);
    }

    public function test_no_params_still_returns_all_bookings(): void
    {
        $user = User::factory()->create();
        $band = Bands::create([
            'name' => 'Band', 'site_name' => 'b-' . uniqid(), 'is_personal' => false,
        ]);
        BandOwners::create(['user_id' => $user->id, 'band_id' => $band->id]);

        Bookings::factory()->for($band, 'band')->create(['date' => '2020-01-01']);
        Bookings::factory()->for($band, 'band')->create(['date' => '2026-06-01']);
        Bookings::factory()->for($band, 'band')->create(['date' => '2030-12-01']);

        $response = $this->actingAs($user)->getJson('/api/mobile/me/bookings');

        $response->assertOk();
        $this->assertCount(3, $response->json('bookings'));
    }
```

- [ ] **Step 3: Run the new tests, verify 4 of 5 fail (the no-params test should already pass)**

Run from `/home/eddie/github/TTS`:
```bash
php artisan test --filter MeBookingsTest
```
Expect: `test_no_params_still_returns_all_bookings` PASSES (existing behavior preserved). The other 4 either FAIL or pass for the wrong reason. The point is to confirm the new filter logic isn't there yet.

- [ ] **Step 4: Implement the controller change**

Edit `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/BookingsController.php`. Find the `indexForUser` method (around line 67). Right before the `$query = Bookings::query()` line, add the validation block. Then add the `from`/`to` filtering to the query builder, immediately after the existing `if ($request->filled('year'))` block.

Replace this block:

```php
    public function indexForUser(Request $request): JsonResponse
    {
        $user = $request->user();
        // Use bands() not allBands(): subs are authorized at the event level
        // (see User::getEventsAttribute) and bookings carry money/contract info
        // they shouldn't see. Subs get an empty Bookings tab; their assigned
        // events still surface via the Dashboard/events endpoints.
        $bandIds = $user->bands()->pluck('id');

        $query = Bookings::query()
            ->with(['band', 'contacts'])
            ->whereIn('band_id', $bandIds);

        if ($request->filled('status')) {
            $query->where('status', $request->input('status'));
        }

        if ($request->boolean('upcoming')) {
            $query->whereDate('date', '>=', now()->toDateString());
        }

        if ($request->filled('year')) {
            $query->whereYear('date', $request->integer('year'));
        }

        $bookings = $query->orderBy('date', 'desc')->get();

        return response()->json([
            'bookings' => $bookings->map(fn ($b) => $this->formatter->format($b))->values(),
        ]);
    }
```

With:

```php
    public function indexForUser(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'from' => 'nullable|date_format:Y-m-d',
            'to'   => 'nullable|date_format:Y-m-d',
        ]);
        if (
            !empty($validated['from']) &&
            !empty($validated['to']) &&
            $validated['from'] > $validated['to']
        ) {
            abort(422, 'from must be on or before to');
        }

        $user = $request->user();
        // Use bands() not allBands(): subs are authorized at the event level
        // (see User::getEventsAttribute) and bookings carry money/contract info
        // they shouldn't see. Subs get an empty Bookings tab; their assigned
        // events still surface via the Dashboard/events endpoints.
        $bandIds = $user->bands()->pluck('id');

        $query = Bookings::query()
            ->with(['band', 'contacts'])
            ->whereIn('band_id', $bandIds);

        if ($request->filled('status')) {
            $query->where('status', $request->input('status'));
        }

        if ($request->boolean('upcoming')) {
            $query->whereDate('date', '>=', now()->toDateString());
        }

        if ($request->filled('year')) {
            $query->whereYear('date', $request->integer('year'));
        }

        if (!empty($validated['from'])) {
            $query->whereDate('date', '>=', $validated['from']);
        }

        if (!empty($validated['to'])) {
            $query->whereDate('date', '<=', $validated['to']);
        }

        $bookings = $query->orderBy('date', 'desc')->get();

        return response()->json([
            'bookings' => $bookings->map(fn ($b) => $this->formatter->format($b))->values(),
        ]);
    }
```

- [ ] **Step 5: Run the tests again, verify all 5 new tests pass**

Run from `/home/eddie/github/TTS`:
```bash
php artisan test --filter MeBookingsTest
```
Expect: all `MeBookingsTest` tests pass (existing + 5 new).

- [ ] **Step 6: Commit (Laravel repo)**

Run from `/home/eddie/github/TTS`:
```bash
git add app/Http/Controllers/Api/Mobile/BookingsController.php tests/Feature/Api/Mobile/MeBookingsTest.php
git commit -m "feat(api): add from/to date-range params to /me/bookings"
```

---

## Task 2: Client repository — forward `from`/`to`

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/bookings/data/bookings_repository.dart` — `getAllUserBookings` signature + body
- Modify: `/home/eddie/github/tts_bandmate/test/features/bookings/bookings_repository_user_bookings_test.dart` — add 3 new tests

Working directory for all client tasks: `/home/eddie/github/tts_bandmate`.

- [ ] **Step 1: Add the failing tests**

Edit `test/features/bookings/bookings_repository_user_bookings_test.dart`. Inside the existing `group('BookingsRepository.getAllUserBookings', () { ... })` block, after the `'omits unset filter params'` test, add:

```dart
    test('passes from + to as YYYY-MM-DD query params', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {'bookings': []});
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;

      final repo = BookingsRepository(dio);
      await repo.getAllUserBookings(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 6, 30),
      );

      expect(adapter.lastRequest!.queryParameters, equals({
        'from': '2026-01-01',
        'to': '2026-06-30',
      }));
    });

    test('passes only from when to is null', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {'bookings': []});
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;

      final repo = BookingsRepository(dio);
      await repo.getAllUserBookings(from: DateTime(2026, 3, 15));

      expect(adapter.lastRequest!.queryParameters, equals({'from': '2026-03-15'}));
    });

    test('passes only to when from is null', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {'bookings': []});
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;

      final repo = BookingsRepository(dio);
      await repo.getAllUserBookings(to: DateTime(2026, 12, 31));

      expect(adapter.lastRequest!.queryParameters, equals({'to': '2026-12-31'}));
    });
```

- [ ] **Step 2: Run the new tests, verify they fail**

Run:
```bash
flutter test test/features/bookings/bookings_repository_user_bookings_test.dart
```
Expect: 3 new tests fail with "named parameter 'from' isn't defined" (compile error).

- [ ] **Step 3: Update the repository signature and body**

Edit `lib/features/bookings/data/bookings_repository.dart`. Replace the `getAllUserBookings` method (around line 50) with:

```dart
  /// Fetches bookings across all bands the authenticated user belongs to
  /// (owners + members only — subs are excluded server-side because bookings
  /// carry money/contract info subs shouldn't see).
  ///
  /// Used by the multi-band Bookings tab. Filters mirror [getBandBookings].
  /// [from] / [to] narrow to a date range (inclusive); pass either or both
  /// in `YYYY-MM-DD` form on the wire.
  Future<List<BookingSummary>> getAllUserBookings({
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
    final rawList = data['bookings'] as List<dynamic>;
    return rawList
        .cast<Map<String, dynamic>>()
        .map(BookingSummary.fromJson)
        .toList();
  }

  /// Formats [d] as `YYYY-MM-DD`. Time-of-day is dropped.
  static String _formatDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
```

- [ ] **Step 4: Run all repository tests, verify all pass**

Run:
```bash
flutter test test/features/bookings/bookings_repository_user_bookings_test.dart
```
Expect: 6 tests pass (3 existing + 3 new).

- [ ] **Step 5: Run the full project analyzer**

Run:
```bash
flutter analyze
```
Expect: `No issues found!` (the change is purely additive).

- [ ] **Step 6: Commit**

```bash
git add lib/features/bookings/data/bookings_repository.dart \
        test/features/bookings/bookings_repository_user_bookings_test.dart
git commit -m "feat(bookings): repo getAllUserBookings supports from/to range"
```

---

## Task 3: Add `clockProvider`

**Files:**
- Create: `lib/features/bookings/providers/clock_provider.dart`
- Test: none on its own (exercised through `bookingsWindowProvider` tests in Task 5)

This is a tiny seam for deterministic "now" in tests.

- [ ] **Step 1: Create the file**

```dart
// lib/features/bookings/providers/clock_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Returns the current `DateTime` when called. Override in tests to pin
/// "now" for deterministic date-range math.
///
/// ```dart
/// // In a test:
/// container = ProviderContainer(overrides: [
///   clockProvider.overrideWithValue(() => DateTime(2026, 5, 3, 12, 0)),
/// ]);
/// ```
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);
```

- [ ] **Step 2: Verify it analyzes**

Run:
```bash
flutter analyze lib/features/bookings/providers/clock_provider.dart
```
Expect: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/bookings/providers/clock_provider.dart
git commit -m "feat(bookings): add clockProvider seam for deterministic now"
```

---

## Task 4: Add `BookingsWindow` value class

**Files:**
- Create: `lib/features/bookings/providers/bookings_window_provider.dart` (the value class first; notifier added in Task 5)
- Test: covered by Task 5's notifier tests

The value class is small, pure, and has its own equality/copyWith. We could TDD it, but the surface is small enough that a clean spec-match is fine; the notifier tests in Task 5 will exercise the fields end-to-end.

- [ ] **Step 1: Create the file with just the value class**

```dart
// lib/features/bookings/providers/bookings_window_provider.dart
import 'package:collection/collection.dart';

import '../data/models/booking_summary.dart';

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
```

- [ ] **Step 2: Verify it analyzes**

Run:
```bash
flutter analyze lib/features/bookings/providers/bookings_window_provider.dart
```
Expect: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/bookings/providers/bookings_window_provider.dart
git commit -m "feat(bookings): add BookingsWindow value class"
```

---

## Task 5: Add `BookingsWindowNotifier` + provider, with full TDD

**Files:**
- Modify: `lib/features/bookings/providers/bookings_window_provider.dart` (append the notifier + provider)
- Create: `test/features/bookings/providers/bookings_window_provider_test.dart`

This task adds the notifier with full unit tests for `build`, `loadEarlier`, `loadLater`, edge detection, in-flight guarding, and `refresh`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/bookings/providers/bookings_window_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Future<List<BookingSummary>> getAllUserBookings({
    String? status,
    bool upcomingOnly = false,
    int? year,
    DateTime? from,
    DateTime? to,
  }) async {
    calls.add((from: from, to: to));
    if (_responseIdx >= responsesQueue.length) return const [];
    return responsesQueue[_responseIdx++];
  }

  // The other repo methods aren't used by the window provider.
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BookingSummary _b(int id, String date) => BookingSummary(
      id: id,
      name: 'b$id',
      date: date,
      isPaid: false,
      contacts: const [],
    );

ProviderContainer _container({
  required _StubRepo repo,
  required DateTime now,
}) {
  return ProviderContainer(overrides: [
    bookingsRepositoryProvider.overrideWithValue(repo),
    clockProvider.overrideWithValue(() => now),
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
      expect(repo.calls.first.to, DateTime(2026, 11, 30));
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
      expect(window.to, DateTime(2026, 11, 30));
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
      expect(window.to, DateTime(2026, 11, 30));
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
          [_b(2, '2027-02-01')], // later
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await c.read(bookingsWindowProvider.notifier).loadLater();

      expect(repo.calls, hasLength(2));
      // current.to was 2026-11-30 → newFrom 2026-12-01, newTo 2027-05-31.
      expect(repo.calls[1].from, DateTime(2026, 12, 1));
      expect(repo.calls[1].to, DateTime(2027, 5, 31));
    });

    test('appends new bookings and advances to', () async {
      final repo = _StubRepo()
        ..responsesQueue = [
          [_b(1, '2026-04-15')],
          [_b(2, '2027-02-01')],
        ];
      final c = _container(repo: repo, now: DateTime(2026, 5, 15));
      addTearDown(c.dispose);

      await c.read(bookingsWindowProvider.future);
      await c.read(bookingsWindowProvider.notifier).loadLater();

      final window = c.read(bookingsWindowProvider).value!;
      expect(window.bookings.map((b) => b.id).toList(), [1, 2]);
      expect(window.to, DateTime(2027, 5, 31));
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
      expect(window.to, DateTime(2026, 11, 30)); // unchanged
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
      expect(repo.calls[1].to, DateTime(2026, 11, 30));
    });
  });
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run:
```bash
flutter test test/features/bookings/providers/bookings_window_provider_test.dart
```
Expect: compilation errors — `BookingsWindowNotifier` and `bookingsWindowProvider` don't exist yet.

- [ ] **Step 3: Implement the notifier and provider**

Append to `lib/features/bookings/providers/bookings_window_provider.dart` (after the existing `BookingsWindow` class):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bookings_repository.dart';
import 'clock_provider.dart';

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

    final repo = ref.read(bookingsRepositoryProvider);
    final bookings = await repo.getAllUserBookings(from: from, to: to);

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

  Future<void> loadEarlier() async {
    final value = state.value;
    if (value == null) return;
    if (value.isLoadingEarlier || value.reachedEarliest) return;

    state = AsyncData(value.copyWith(isLoadingEarlier: true));

    final newFrom = DateTime(
      value.from.year,
      value.from.month - _expansionMonths,
      value.from.day,
    );
    final newTo = value.from.subtract(const Duration(days: 1));

    try {
      final repo = ref.read(bookingsRepositoryProvider);
      final fetched = await repo.getAllUserBookings(from: newFrom, to: newTo);

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
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> loadLater() async {
    final value = state.value;
    if (value == null) return;
    if (value.isLoadingLater || value.reachedLatest) return;

    state = AsyncData(value.copyWith(isLoadingLater: true));

    final newFrom = value.to.add(const Duration(days: 1));
    final newTo = DateTime(
      value.to.year,
      value.to.month + _expansionMonths,
      value.to.day,
    );

    try {
      final repo = ref.read(bookingsRepositoryProvider);
      final fetched = await repo.getAllUserBookings(from: newFrom, to: newTo);

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
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Re-runs `build` from scratch — refetches the initial window.
  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  static List<BookingSummary> _sortAscByDate(List<BookingSummary> input) {
    final sorted = [...input];
    sorted.sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
    return sorted;
  }
}

final bookingsWindowProvider =
    AsyncNotifierProvider<BookingsWindowNotifier, BookingsWindow>(
  BookingsWindowNotifier.new,
);
```

- [ ] **Step 4: Run tests, verify they pass**

Run:
```bash
flutter test test/features/bookings/providers/bookings_window_provider_test.dart
```
Expect: all 11 tests pass.

- [ ] **Step 5: Run analyzer**

Run:
```bash
flutter analyze lib/features/bookings/providers/bookings_window_provider.dart \
  test/features/bookings/providers/bookings_window_provider_test.dart
```
Expect: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/bookings/providers/bookings_window_provider.dart \
        test/features/bookings/providers/bookings_window_provider_test.dart
git commit -m "feat(bookings): add bookingsWindowProvider with load earlier/later"
```

---

## Task 6: Drop `userBookingsProvider`

**Files:**
- Modify: `lib/features/bookings/providers/bookings_provider.dart` — remove the `userBookingsProvider` declaration
- Modify: `test/providers/user_bookings_provider_test.dart` — delete (its single test exercises the soon-to-be-removed provider; the equivalent assertion now lives in the repo and window-provider tests)

Note: `userBookingsProvider` is consumed by the screen. Removing it temporarily breaks the build until Task 7 fixes the screen. That's expected and matches the pattern from the prior refactor in the styling work.

- [ ] **Step 1: Read the current screen call sites**

Run:
```bash
grep -n "userBookingsProvider" /home/eddie/github/tts_bandmate/lib/features/bookings/screens/bookings_screen.dart
```
Expect: a handful of call sites (`ref.watch`, `ref.listen`, `ref.read(...).value`, `ref.invalidate`).

These are intentionally left broken in this commit — Task 7 fixes them. Do NOT touch the screen file in this task.

- [ ] **Step 2: Remove the provider from `bookings_provider.dart`**

Edit `lib/features/bookings/providers/bookings_provider.dart`. Delete the block:

```dart
// ── User bookings (multi-band) ────────────────────────────────────────────────

final userBookingsProvider = FutureProvider<List<BookingSummary>>((ref) {
  final repo = ref.watch(bookingsRepositoryProvider);
  return repo.getAllUserBookings();
});
```

Keep everything else in the file unchanged.

- [ ] **Step 3: Delete the obsolete user-bookings provider test**

Run:
```bash
rm test/providers/user_bookings_provider_test.dart
```

The single remaining test in that file (`'userBookingsProvider fetches via /api/mobile/me/bookings'`) is now redundant: the wire-level assertion is covered by `test/features/bookings/bookings_repository_user_bookings_test.dart`, and the call-site assertion will be covered by the window provider tests added in Task 5.

- [ ] **Step 4: Confirm the analyzer reports the expected breakage in the screen**

Run:
```bash
flutter analyze
```
Expect: errors in `lib/features/bookings/screens/bookings_screen.dart` referencing the removed `userBookingsProvider`. Other errors should be unrelated pre-existing warnings only. Note the count for sanity — Task 7 should bring it back to clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/bookings/providers/bookings_provider.dart \
        test/providers/user_bookings_provider_test.dart
git commit -m "refactor(bookings): drop userBookingsProvider in favor of window provider"
```

---

## Task 7: Wire the screen to `bookingsWindowProvider` and add edge detection

**Files:**
- Modify: `lib/features/bookings/screens/bookings_screen.dart` — switch to window provider, add edge detection, add scroll anchor on prepend, add sentinel-spinner rows, plumb sentinel-index translation

This is the largest task in this plan. The screen rewrite has multiple cooperating pieces; do them in the order listed and run the existing screen widget test after each piece to keep the change reversible if something breaks.

- [ ] **Step 1: Read the current screen file end-to-end**

Run:
```bash
wc -l lib/features/bookings/screens/bookings_screen.dart
sed -n '1,80p' lib/features/bookings/screens/bookings_screen.dart
```
Expect: a `_BookingsScreenState` class with fields `_searchController`, `_query`, `_selectedMonthKey`, `_lastJumpedFingerprint`, `_initialJumpDone`, `_itemScrollController`, `_itemPositionsListener`, `_chipScrollController`, `_monthHeaderIndex`, `_monthKeys`. Refresh memory before editing.

- [ ] **Step 2: Add the new state fields, the import, and the sentinel-translation helpers**

Edit `lib/features/bookings/screens/bookings_screen.dart`. At the top of the file, add the import next to the other relative imports:

```dart
import '../providers/bookings_window_provider.dart';
```

Inside `_BookingsScreenState`, alongside the existing state fields, add:

```dart
  // Edge detection / scroll anchor (windowed loading).
  int _renderedItemCount = 0;
  ({int bookingId, double leadingEdge})? _scrollAnchor;
```

Right under the existing comment region for "Month strip / scrolling", add three small helpers:

```dart
  // ── Sentinel index helpers (windowed loading) ──────────────────────────────

  /// Number of spinner sentinel rows currently rendered above the real
  /// items list. Either 0 or 1, mirroring `window.isLoadingEarlier`.
  int get _topSentinels {
    final w = ref.read(bookingsWindowProvider).value;
    return (w?.isLoadingEarlier ?? false) ? 1 : 0;
  }

  /// Number of spinner sentinel rows currently rendered below the real
  /// items list.
  int get _bottomSentinels {
    final w = ref.read(bookingsWindowProvider).value;
    return (w?.isLoadingLater ?? false) ? 1 : 0;
  }
```

- [ ] **Step 3: Update `_onItemPositionsChange` to translate indices and add edge detection**

Replace the body of `_onItemPositionsChange` with:

```dart
  void _onItemPositionsChange() {
    if (!mounted) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final topSentinels = _topSentinels;

    // Translate raw builder indices into data.items indices and drop the
    // sentinels (negative indices, or indices beyond the real list).
    final itemIndices = positions
        .map((p) => p.index - topSentinels)
        .where((i) => i >= 0 && i < _renderedItemCount)
        .toList();

    // ── Chip-highlight ──
    if (itemIndices.isNotEmpty) {
      final firstVisible =
          itemIndices.fold<int>(itemIndices.first, (a, b) => a < b ? a : b);
      String? topMonth;
      int bestIdx = -1;
      for (final entry in _monthHeaderIndex.entries) {
        if (entry.value <= firstVisible && entry.value > bestIdx) {
          bestIdx = entry.value;
          topMonth = entry.key;
        }
      }
      if (topMonth != null && topMonth != _selectedMonthKey) {
        setState(() => _selectedMonthKey = topMonth);
        _ensureChipVisible(topMonth);
      }
    }

    // ── Edge detection (auto-load) ──
    final window = ref.read(bookingsWindowProvider).value;
    if (window == null || _renderedItemCount == 0) return;
    final notifier = ref.read(bookingsWindowProvider.notifier);

    // Use raw positions for edge math (so the sentinel itself counts as
    // "near the edge" — that's correct: if the spinner is on screen, we
    // have already scrolled to the boundary).
    final firstRaw =
        positions.map((p) => p.index).reduce((a, b) => a < b ? a : b);
    final lastRaw =
        positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    final totalCount = _renderedItemCount + topSentinels + _bottomSentinels;

    if (firstRaw <= 10 &&
        !window.reachedEarliest &&
        !window.isLoadingEarlier) {
      _captureScrollAnchor();
      notifier.loadEarlier();
    }
    if (lastRaw >= totalCount - 10 &&
        !window.reachedLatest &&
        !window.isLoadingLater) {
      notifier.loadLater();
    }
  }

  /// Captures the topmost visible `_CardItem`'s booking ID + leading edge
  /// so the screen can restore scroll position after `loadEarlier`
  /// prepends new items.
  void _captureScrollAnchor() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final topSentinels = _topSentinels;

    // Walk visible positions from top down; pick the first one whose
    // data.items entry is a _CardItem.
    final sorted = positions.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    for (final pos in sorted) {
      final dataIdx = pos.index - topSentinels;
      if (dataIdx < 0 || dataIdx >= _renderedItemCount) continue;
      final item = _currentItems.elementAtOrNull(dataIdx);
      if (item is _CardItem) {
        _scrollAnchor = (
          bookingId: item.booking.id,
          leadingEdge: pos.itemLeadingEdge,
        );
        return;
      }
    }
    // No card visible — leave anchor null.
  }
```

Note: this references `_currentItems` (the latest `data.items` cached on the state) and `List<int>.fold` — both of which need a small companion add. Add a field next to `_renderedItemCount`:

```dart
  List<_ListItem> _currentItems = const [];
```

(`elementAtOrNull` is in `dart:collection`'s `Iterable` extension since Dart 3.0 — no import needed.)

- [ ] **Step 4: Update `_onMonthChipTap` and `_maybeJumpToNearest` to add `_topSentinels` to controller calls**

Replace the body of `_onMonthChipTap`:

```dart
  void _onMonthChipTap(String monthKey) {
    setState(() => _selectedMonthKey = monthKey);
    final index = _monthHeaderIndex[monthKey];
    if (index != null && _itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: index + _topSentinels,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _ensureChipVisible(monthKey);
  }
```

In `_maybeJumpToNearest`, change the `_itemScrollController.jumpTo` call from:

```dart
        _itemScrollController.jumpTo(index: headerIndex);
```

to:

```dart
        _itemScrollController.jumpTo(index: headerIndex + _topSentinels);
```

- [ ] **Step 5: Switch the data-source watch and listen calls**

Find the `build` method. Replace:

```dart
    ref.listen<AsyncValue<List<BookingSummary>>>(userBookingsProvider,
        (_, next) {
      final data = next.value;
      if (data == null) return;
      _maybeJumpToNearest(_filteredSorted(data, ref.read(bookingsFilterProvider)));
    });

    ref.listen<BookingsFilterState>(bookingsFilterProvider, (_, __) {
      final data = ref.read(userBookingsProvider).value;
      if (data == null) return;
      _maybeJumpToNearest(_filteredSorted(data, ref.read(bookingsFilterProvider)));
    });

    final bookingsAsync = ref.watch(userBookingsProvider);
```

With:

```dart
    ref.listen<AsyncValue<BookingsWindow>>(bookingsWindowProvider,
        (_, next) {
      final window = next.value;
      if (window == null) return;
      _maybeJumpToNearest(
          _filteredSorted(window.bookings, ref.read(bookingsFilterProvider)));
    });

    ref.listen<BookingsFilterState>(bookingsFilterProvider, (_, __) {
      final window = ref.read(bookingsWindowProvider).value;
      if (window == null) return;
      _maybeJumpToNearest(
          _filteredSorted(window.bookings, ref.read(bookingsFilterProvider)));
    });

    final bookingsAsync = ref.watch(bookingsWindowProvider);
```

- [ ] **Step 6: Update the `data:` builder to destructure `BookingsWindow`, cache `_currentItems` / `_renderedItemCount`, and restore scroll anchor**

Find the `data: (bookings) { ... }` block. Replace its body with:

```dart
                        data: (window) {
                          final data =
                              _buildListData(window.bookings, filter, _query);
                          _monthHeaderIndex = data.monthHeaderIndex;
                          _monthKeys = data.monthKeys;
                          _currentItems = data.items;
                          _renderedItemCount = data.items.length;

                          if (!_initialJumpDone) {
                            _initialJumpDone = true;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              _maybeJumpToNearest(data.visibleAfterFilter);
                            });
                          }

                          // Restore scroll anchor after a prepend (loadEarlier).
                          final anchor = _scrollAnchor;
                          if (anchor != null) {
                            _scrollAnchor = null;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              if (!_itemScrollController.isAttached) return;
                              for (var i = 0; i < data.items.length; i++) {
                                final item = data.items[i];
                                if (item is _CardItem &&
                                    item.booking.id == anchor.bookingId) {
                                  _itemScrollController.jumpTo(
                                    index: i + _topSentinels,
                                    alignment: anchor.leadingEdge,
                                  );
                                  break;
                                }
                              }
                            });
                          }

                          return Column(
                            children: [
                              if (data.monthKeys.isNotEmpty)
                                BookingsMonthStrip(
                                  monthKeys: data.monthKeys,
                                  selectedKey: _selectedMonthKey,
                                  onTap: _onMonthChipTap,
                                  chipScrollController: _chipScrollController,
                                ),
                              Expanded(
                                child: _buildContent(context, ref, data, filter,
                                    window: window),
                              ),
                            ],
                          );
                        },
```

(Note: `_buildContent` now also takes the `window` so it can read the loading flags — see next step.)

Also update the `error:` branch's `onRetry` to call the new provider:

```dart
                        error: (e, _) => ErrorView(
                          message: ErrorView.friendlyMessage(e),
                          onRetry: () => ref.invalidate(bookingsWindowProvider),
                        ),
```

- [ ] **Step 7: Update `_buildContent` to accept `window` and inflate the SliverList builder with sentinel rows**

Change the `_buildContent` method signature to:

```dart
  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ({
      List<BookingSummary> visibleAfterFilter,
      List<_ListItem> items,
      List<String> monthKeys,
      Map<String, int> monthHeaderIndex,
    }) data,
    BookingsFilterState filter, {
    required BookingsWindow window,
  }) {
```

Find the `ScrollablePositionedList.builder(...)` call inside `_buildContent`. Replace with:

```dart
          : ScrollablePositionedList.builder(
              itemCount: data.items.length +
                  (window.isLoadingEarlier ? 1 : 0) +
                  (window.isLoadingLater ? 1 : 0),
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              itemBuilder: (context, index) {
                final topSentinels = window.isLoadingEarlier ? 1 : 0;
                final dataIdx = index - topSentinels;
                if (dataIdx < 0) {
                  return const _LoadingSentinel();
                }
                if (dataIdx >= data.items.length) {
                  return const _LoadingSentinel();
                }
                final item = data.items[dataIdx];
                return switch (item) {
                  _HeaderItem(:final label, :final monthKey) =>
                    _MonthHeader(label: label),
                  _CardItem(:final booking) => _BookingCard(
                      booking: booking,
                      onTap: () {
                        final bandId = booking.band?.id;
                        if (bandId != null) {
                          context.push(
                            '/bookings/$bandId/${booking.id}',
                          );
                        }
                      },
                    ),
                };
              },
            ),
```

(Note: Dart's switch-on-sealed already has `_HeaderItem(:final monthKey)` here even though `monthKey` isn't used — the destructure pattern matches what's in the existing screen file, keep it as-is.)

- [ ] **Step 8: Add the `_LoadingSentinel` widget**

At the bottom of `lib/features/bookings/screens/bookings_screen.dart` (just before the file's closing or among the other private widgets), add:

```dart
class _LoadingSentinel extends StatelessWidget {
  const _LoadingSentinel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: CupertinoActivityIndicator(),
      ),
    );
  }
}
```

- [ ] **Step 9: Run the analyzer**

Run:
```bash
flutter analyze lib/features/bookings/screens/bookings_screen.dart
```
Expect: `No issues found!`. If anything fails, fix in place — common issues are missing imports (add the `bookings_window_provider.dart` import, the `BookingsWindow` reference) or type mismatches in the `bookingsAsync.when` branches.

- [ ] **Step 10: Run the existing screen widget test**

Run:
```bash
flutter test test/features/bookings/bookings_screen_multi_band_test.dart
```
Expect: PASS. The test stubs the HTTP layer at the Dio adapter level, so it doesn't care which provider is used as long as the URL is the same — and `bookingsWindowProvider` hits the same `/api/mobile/me/bookings` path. The test expects 'Big Show', 'Sunday Service', 'The Rocking Eds', 'Personal' to render — all should still appear because the test's bookings (dated `${now.year}-06-01` and `${now.year}-06-02`) fall inside the initial 12-month window when run today.

If the test fails because the dates fall outside the window math, adjust the test fixture dates — but check the failure first. The test should ideally pass without changes.

- [ ] **Step 11: Run the full project analyzer**

Run:
```bash
flutter analyze
```
Expect: `No issues found!` (the same pre-existing warnings as before — `unnecessary_non_null_assertion`, deprecated `encryptedSharedPreferences`, two Sentry experimental warnings, three unused imports in `band_settings_repository_test.dart`, one unused local in `events_provider_test.dart`).

- [ ] **Step 12: Run the full test suite**

Run:
```bash
flutter test
```
Expect: 264 tests pass (256 previous + 11 new from Task 5 + 3 new from Task 2 − 1 deleted from Task 6 = 269... actually count is: 256 + 11 + 3 − 1 = 269, but the screen test from Task 11 of the styling work is already counted in 256, and Task 6 deletes one; so final expected is 256 + 11 + 3 − 1 = 269). The exact number isn't important — what matters is that no new failures appear vs. the count after Task 5.

- [ ] **Step 13: Commit**

```bash
git add lib/features/bookings/screens/bookings_screen.dart
git commit -m "feat(bookings): wire screen to bookingsWindowProvider with auto-load"
```

---

## Task 8: Final verification

- [ ] **Step 1: Run the full client test suite**

Run:
```bash
flutter test
```
Expect: PASS, no new failures.

- [ ] **Step 2: Run the full client analyzer**

Run:
```bash
flutter analyze
```
Expect: only the pre-existing warnings.

- [ ] **Step 3: Run the Laravel test suite (if you have it set up locally)**

Run from `/home/eddie/github/TTS`:
```bash
php artisan test --filter MeBookingsTest
```
Expect: PASS. (If the Laravel environment isn't set up locally, skip and rely on CI.)

- [ ] **Step 4: Push the Flutter branch**

Run from `/home/eddie/github/tts_bandmate`:
```bash
git push
```

- [ ] **Step 5: Smoke-test in chrome**

Run:
```bash
flutter run -d chrome --dart-define-from-file=.dart_defines/local.json
```

Manual check on the Bookings tab:
- Initial load — payload should contain only ~12 months of bookings (verify in DevTools Network: the `/api/mobile/me/bookings` request should have `?from=...&to=...` query params).
- Scroll to within ~10 items of the bottom — the `/api/mobile/me/bookings` request fires again with `from=` matching the previous `to + 1 day` and `to=` 6 months later. A small spinner shows below the list during the fetch. New bookings append.
- Scroll to within ~10 items of the top — same on the earlier side. A small spinner shows above. The booking the user was looking at stays in roughly the same screen position after the prepend (scroll-anchor working).
- Filter to "Confirmed" — instant, no network. Scroll to bottom of the (sparse) filtered list — `loadLater` fires, more bookings come in, more confirmed-status items appear after the filter re-applies.
- Once the band's earliest/latest data is exhausted, the spinner stops appearing on further edge scrolls.

- [ ] **Step 6: No commit needed — already covered by previous commits.**

---

## Self-review notes (for the engineer reading this)

- **Spec coverage:** every spec section has a task. Backend (Task 1), repository (Task 2), clock seam (Task 3), value class (Task 4), notifier (Task 5), provider removal (Task 6), screen wiring (Task 7), final verification (Task 8).
- **Type consistency:** `BookingsWindow` is the value class throughout. `bookingsWindowProvider` is the consistent name. `_topSentinels` / `_bottomSentinels` getters are used in three places (`_onItemPositionsChange`, `_onMonthChipTap`, `_maybeJumpToNearest`, the `data:` anchor restore, the `_buildContent` `itemBuilder`). `_currentItems` and `_renderedItemCount` are written in the `data:` builder and read by `_captureScrollAnchor`.
- **Open items the spec called out:**
  - Negative-month `DateTime` normalization: the notifier code uses `DateTime(now.year, now.month - 3, 1)` and `DateTime(now.year, now.month + 10, 0)` — both rely on Dart's normalization. The Task 5 tests pin "now" to `2026-05-15` and assert the resulting from/to are `2026-02-01` and `2026-11-30`, which proves the normalization works for the intended cases.
  - `ItemPositions.itemLeadingEdge` semantics: the smoke test in Task 8 verifies the anchor lands the booking in the same visual position.
  - `from`/`to` composition with existing `status`/`year` filters: the controller change preserves all existing filter blocks unchanged and just appends two more `whereDate` clauses; Eloquent's query builder ANDs them together by default.
- **Backwards compatibility:** the `getAllUserBookings` repo method keeps `status`, `upcomingOnly`, `year` parameters; only the screen has been migrated to use the window provider, so any other caller (none today) would continue to work.
