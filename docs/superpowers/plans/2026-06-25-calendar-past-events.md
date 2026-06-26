# Calendar Past Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The mobile dashboard calendar shows the past 30 days of events on load, and lazily fetches older events 30 days at a time when the user swipes back past the loaded range.

**Architecture:** Backend widens the mobile dashboard's initial window to `now - 30d` and adds a `load-older` endpoint mirroring the web app's existing `loadOlderEvents`. The Flutter dashboard provider tracks a `loadedFrom` watermark (earliest loaded date, only moves backward), merges+dedups fetched chunks by event id, and the calendar screen triggers a fetch only when the focused month's first day is strictly before that watermark.

**Tech Stack:** Laravel 10 (PHP 8) backend in `/home/eddie/github/TTS` (run via `docker compose exec app`); Flutter/Dart with Riverpod v2 `AsyncNotifier` and the `table_calendar` package in `tts_bandmate`.

**IMPORTANT — two repos:**
- Backend tasks (1–2) run in `/home/eddie/github/TTS`. Per project convention, run all PHP/artisan/test commands inside the container: `docker compose exec app …`. NEVER run php/artisan/phpunit on the host.
- Frontend tasks (3–6) run in this repo (`tts_bandmate`), branch `feat/calendar-past-events`.
- The backend changes must be merged/deployed (staging auto-deploys on merge) before the frontend `load-older` calls will succeed against staging, but the two can be developed and committed independently.

---

## File Structure

**Backend (`/home/eddie/github/TTS`):**
- Modify: `app/Http/Controllers/Api/Mobile/DashboardController.php` — widen `index()` window; add `loadOlder()`.
- Modify: `routes/api.php` — add `mobile.dashboard.load-older` route next to `mobile.dashboard`.
- Modify: `tests/Feature/Api/Mobile/DashboardTest.php` — tests for past-window and `load-older`.

**Frontend (`tts_bandmate`):**
- Modify: `lib/core/network/api_endpoints.dart` — add `mobileDashboardLoadOlder` constant.
- Modify: `lib/features/dashboard/data/dashboard_repository.dart` — add `loadOlderEvents()`.
- Modify: `lib/features/dashboard/providers/dashboard_provider.dart` — add `loadedFrom` / `isLoadingOlder` / `hasReachedStart` to state; add `loadOlder()` to notifier; widen `build()` window awareness.
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart` — watermark-triggered fetch in `onPageChanged`; loading indicator.
- Create: `test/features/dashboard/dashboard_provider_test.dart` — provider unit + navigation tests.

---

## Task 1: Backend — widen initial dashboard window + add `loadOlder` endpoint

**Files:**
- Modify: `app/Http/Controllers/Api/Mobile/DashboardController.php`
- Modify: `routes/api.php` (near line 91, the `mobile.dashboard` route)

All commands run from `/home/eddie/github/TTS`.

- [ ] **Step 1: Add the route**

In `routes/api.php`, directly after the existing dashboard route (line ~91):

```php
// Dashboard
Route::get('/dashboard', [App\Http\Controllers\Api\Mobile\DashboardController::class, 'index'])->name('mobile.dashboard');
Route::get('/dashboard/load-older', [App\Http\Controllers\Api\Mobile\DashboardController::class, 'loadOlder'])->name('mobile.dashboard.load-older');
```

- [ ] **Step 2: Widen `index()` window and add `loadOlder()`**

Replace the body of `app/Http/Controllers/Api/Mobile/DashboardController.php` with (adds `use Carbon`, passes explicit `afterDate` to `index`, adds `loadOlder`):

```php
<?php

namespace App\Http\Controllers\Api\Mobile;

use App\Http\Controllers\Controller;
use App\Services\Mobile\DashboardFormatter;
use App\Services\UserEventsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;

class DashboardController extends Controller
{
    /** Days of past events to include in the initial dashboard payload. */
    private const INITIAL_PAST_WINDOW_DAYS = 30;

    public function __construct(private readonly DashboardFormatter $formatter) {}

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        // UserEventsService uses Auth::user() internally. Sanctum token auth does not
        // set the session guard, so we must manually bind the user to the Auth guard
        // before invoking the service. We use setUser() rather than login() to avoid
        // firing login events.
        Auth::setUser($user);

        // Mobile shows a calendar (not the web feed), so include the recent past.
        $afterDate = Carbon::now()->subDays(self::INITIAL_PAST_WINDOW_DAYS);

        $events         = (new UserEventsService())->getEvents($afterDate);
        $upcomingCharts = (new UserEventsService())->getUpcomingCharts();

        $collection = $events instanceof \Illuminate\Support\Collection
            ? $events
            : collect($events);

        $normalized = $this->formatter->formatEvents($collection);

        return response()->json([
            'events'          => $normalized,
            'upcoming_charts' => $upcomingCharts instanceof \Illuminate\Support\Collection
                ? $upcomingCharts->values()
                : collect($upcomingCharts)->values(),
        ]);
    }

    /**
     * Load an older 30-day window of events for the calendar's lazy back-fetch.
     * Mirrors the web DashboardController::loadOlderEvents pattern.
     */
    public function loadOlder(Request $request): JsonResponse
    {
        $beforeDateInput = $request->input('before_date');

        if (! $beforeDateInput) {
            return response()->json(['events' => []]);
        }

        Auth::setUser($request->user());

        $beforeDate = Carbon::parse($beforeDateInput);
        $afterDate  = $beforeDate->copy()->subDays(30);

        $events = (new UserEventsService())->getEvents($afterDate, $beforeDate);

        $collection = $events instanceof \Illuminate\Support\Collection
            ? $events
            : collect($events);

        return response()->json([
            'events' => $this->formatter->formatEvents($collection),
        ]);
    }
}
```

- [ ] **Step 3: Sanity-check routes register**

Run: `docker compose exec app php artisan route:list --name=mobile.dashboard`
Expected: two rows — `mobile.dashboard` and `mobile.dashboard.load-older`.

- [ ] **Step 4: Commit**

```bash
git add app/Http/Controllers/Api/Mobile/DashboardController.php routes/api.php
git commit -m "feat(mobile): widen dashboard window to 30d past + add load-older endpoint"
```

---

## Task 2: Backend — feature tests for past window + `load-older`

**Files:**
- Modify: `tests/Feature/Api/Mobile/DashboardTest.php`

All commands run from `/home/eddie/github/TTS`.

- [ ] **Step 1: Write the failing tests**

Append these three methods inside the `DashboardTest` class (before the closing brace). They follow the existing fixture style in this file (owner band + booking event):

```php
    public function test_dashboard_includes_events_from_the_past_30_days(): void
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $eventType = EventTypes::factory()->create();
        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        Events::factory()->create([
            'eventable_id'   => $booking->id,
            'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id'  => $eventType->id,
            'date'           => now()->subDays(10)->format('Y-m-d'),
        ]);

        $token = $user->createToken('test-device')->plainTextToken;

        $response = $this->withToken($token)->getJson('/api/mobile/dashboard');

        $response->assertOk();
        $this->assertCount(1, $response->json('events'), 'expected the 10-day-old event in the past-30d window');
    }

    public function test_load_older_returns_events_in_the_requested_past_window(): void
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $eventType = EventTypes::factory()->create();
        $booking = Bookings::factory()->create(['band_id' => $band->id]);
        // 45 days ago: outside the initial 30d window, inside the load-older window.
        Events::factory()->create([
            'eventable_id'   => $booking->id,
            'eventable_type' => 'App\\Models\\Bookings',
            'event_type_id'  => $eventType->id,
            'date'           => now()->subDays(45)->format('Y-m-d'),
        ]);

        $token = $user->createToken('test-device')->plainTextToken;

        // Initial dashboard (30d window) must NOT include the 45-day-old event.
        $initial = $this->withToken($token)->getJson('/api/mobile/dashboard');
        $initial->assertOk();
        $this->assertCount(0, $initial->json('events'));

        // load-older with before_date = now-30d should reach back to now-60d and find it.
        $before = now()->subDays(30)->toDateString();
        $older = $this->withToken($token)->getJson("/api/mobile/dashboard/load-older?before_date={$before}");

        $older->assertOk()->assertJsonStructure(['events']);
        $this->assertCount(1, $older->json('events'), 'expected the 45-day-old event in the load-older window');
    }

    public function test_load_older_returns_empty_when_before_date_missing(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('test-device')->plainTextToken;

        $response = $this->withToken($token)->getJson('/api/mobile/dashboard/load-older');

        $response->assertOk();
        $this->assertSame([], $response->json('events'));
    }

    public function test_load_older_requires_authentication(): void
    {
        $this->getJson('/api/mobile/dashboard/load-older?before_date=2026-01-01')
            ->assertUnauthorized();
    }
```

- [ ] **Step 2: Run the tests**

Run: `docker compose exec app php artisan test --filter=DashboardTest`
Expected: PASS (all existing + 4 new tests green).

If `test_dashboard_includes_events_from_the_past_30_days` fails with 0 events, confirm Task 1 Step 2's `getEvents($afterDate)` change landed.

- [ ] **Step 3: Commit**

```bash
git add tests/Feature/Api/Mobile/DashboardTest.php
git commit -m "test(mobile): cover dashboard past-30d window + load-older endpoint"
```

---

## Task 3: Frontend — add `load-older` endpoint constant + repository method

**Files:**
- Modify: `lib/core/network/api_endpoints.dart:18`
- Modify: `lib/features/dashboard/data/dashboard_repository.dart`

All commands run from this repo (`tts_bandmate`).

- [ ] **Step 1: Add the endpoint constant**

In `lib/core/network/api_endpoints.dart`, directly after line 18 (`static const String mobileDashboard = '/api/mobile/dashboard';`):

```dart
  static const String mobileDashboard = '/api/mobile/dashboard';
  static const String mobileDashboardLoadOlder =
      '/api/mobile/dashboard/load-older';
```

- [ ] **Step 2: Add `loadOlderEvents` to the repository**

In `lib/features/dashboard/data/dashboard_repository.dart`, add this method to the `DashboardRepository` class, after `getDashboard()` (before the closing brace at line 35). `ApiEndpoints` is already available via the `core_providers.dart` re-export imported at the top.

```dart
  /// Fetches an older 30-day window of events for the calendar's lazy
  /// back-fetch. [beforeDate] is an ISO-8601 date string; the server returns
  /// events in [beforeDate - 30d, beforeDate).
  Future<List<EventSummary>> loadOlderEvents(String beforeDate) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileDashboardLoadOlder,
      queryParameters: {'before_date': beforeDate},
    );

    final rawEvents = response.data?['events'] as List<dynamic>? ?? [];
    return rawEvents
        .cast<Map<String, dynamic>>()
        .map(EventSummary.fromJson)
        .toList();
  }
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/features/dashboard/data/dashboard_repository.dart lib/core/network/api_endpoints.dart`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add lib/core/network/api_endpoints.dart lib/features/dashboard/data/dashboard_repository.dart
git commit -m "feat(dashboard): repository method for loading older events"
```

---

## Task 4: Frontend — extend `DashboardState` with watermark fields

**Files:**
- Modify: `lib/features/dashboard/providers/dashboard_provider.dart`
- Test: `test/features/dashboard/dashboard_provider_test.dart` (created here)

This task only adds the immutable state shape + `copyWith` so later tasks can build on it. The notifier logic comes in Task 5.

- [ ] **Step 1: Write the failing test**

Create `test/features/dashboard/dashboard_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';

void main() {
  group('DashboardState.copyWith', () {
    test('defaults: empty, not loading older, start not reached', () {
      final from = DateTime(2026, 6, 1);
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: from,
      );

      expect(state.events, isEmpty);
      expect(state.loadedFrom, from);
      expect(state.isLoadingOlder, isFalse);
      expect(state.hasReachedStart, isFalse);
    });

    test('copyWith overrides only the named fields', () {
      final from = DateTime(2026, 6, 1);
      final earlier = DateTime(2026, 5, 2);
      final state = DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: from,
      );

      final next = state.copyWith(
        loadedFrom: earlier,
        isLoadingOlder: true,
        hasReachedStart: true,
      );

      expect(next.loadedFrom, earlier);
      expect(next.isLoadingOlder, isTrue);
      expect(next.hasReachedStart, isTrue);
      // unchanged
      expect(next.events, same(state.events));
      expect(next.upcomingCharts, same(state.upcomingCharts));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/dashboard/dashboard_provider_test.dart`
Expected: FAIL — compile error, `DashboardState` has no `loadedFrom` / `copyWith`.

- [ ] **Step 3: Extend `DashboardState`**

In `lib/features/dashboard/providers/dashboard_provider.dart`, replace the `DashboardState` constructor and field declarations (lines 9–16) with:

```dart
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
```

(Leave the `currentEvent` getter and `toString()` that follow unchanged.)

- [ ] **Step 4: Fix the two `DashboardState` construction sites in `build()`/`refresh()`**

Still in `dashboard_provider.dart`, the `build()` and `refresh()` methods construct `DashboardState` without `loadedFrom` and will now fail to compile. Update both. Add a private helper constant at the top of the `DashboardNotifier` class and use it.

Replace the `build()` method (lines ~66–79) with:

```dart
  /// Days of past events the initial payload covers — must match the backend
  /// DashboardController::INITIAL_PAST_WINDOW_DAYS.
  static const int _initialPastWindowDays = 30;

  @override
  Future<DashboardState> build() async {
    // Wait for band selection to resolve before fetching — avoids a missing
    // X-Band-ID header on the first request when storage hasn't been read yet.
    final bandId = await ref.watch(selectedBandProvider.future);
    final initialFrom = _dateOnly(
      DateTime.now().subtract(const Duration(days: _initialPastWindowDays)),
    );
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

  /// Truncates a [DateTime] to midnight (date-only) for stable comparisons.
  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
```

Replace the `refresh()` body's return (lines ~84–91) so it preserves the watermark reset to a fresh 30-day window:

```dart
  /// Re-fetches the dashboard from the server, resetting the loaded window.
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/dashboard/dashboard_provider_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/dashboard/providers/dashboard_provider.dart test/features/dashboard/dashboard_provider_test.dart
git commit -m "feat(dashboard): add loadedFrom watermark to DashboardState"
```

---

## Task 5: Frontend — implement `loadOlder()` on the notifier

**Files:**
- Modify: `lib/features/dashboard/providers/dashboard_provider.dart`
- Test: `test/features/dashboard/dashboard_provider_test.dart`

This adds the merge/dedup/guard logic and tests it against a fake repository.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/dashboard/dashboard_provider_test.dart` — new imports at top and a new group. The fake repo records each `before_date` it was asked for and returns scripted events.

Add these imports at the top of the file:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';
import 'package:tts_bandmate/features/dashboard/data/models/upcoming_chart.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
```

(The `dashboard_provider.dart` import may already be present from Task 4 — don't duplicate it.)

And define the shared throwaway Dio used by the fake's super constructor, at file top:

```dart
final _throwingDio = Dio();
```

Add this fake + helper above `void main()`:

```dart
// EventSummary.fromJson does non-null casts on 'key' and 'title' — both are
// required in the payload or fromJson throws. See event_summary.dart:77-78.
EventSummary _event(int id, String date) => EventSummary.fromJson({
      'id': id,
      'key': 'evt-$id',
      'title': 'Event $id',
      'date': date,
      'event_source': 'booking',
    });

/// Fake repository: records requested before_dates, returns scripted batches.
class _FakeDashboardRepository extends DashboardRepository {
  _FakeDashboardRepository({
    required this.initialEvents,
    required this.olderBatches,
  }) : super(_throwingDio);

  final List<EventSummary> initialEvents;

  /// Successive responses for each loadOlderEvents call, in order. When
  /// exhausted, returns an empty list (signals start-of-history).
  final List<List<EventSummary>> olderBatches;

  final List<String> requestedBeforeDates = [];
  int _batchIndex = 0;

  @override
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard() async =>
          (events: initialEvents, upcomingCharts: const <UpcomingChart>[]);

  @override
  Future<List<EventSummary>> loadOlderEvents(String beforeDate) async {
    requestedBeforeDates.add(beforeDate);
    if (_batchIndex >= olderBatches.length) return const [];
    return olderBatches[_batchIndex++];
  }
}
```

> NOTE: the `getDashboard()` override return type is the exact record type from `dashboard_repository.dart:13-14`: `({List<EventSummary> events, List<UpcomingChart> upcomingCharts})`. The `_throwingDio` default `Dio()` only satisfies the super constructor — every network method is overridden so it's never used.

Add this group inside `main()`:

```dart
  group('DashboardNotifier.loadOlder', () {
    late ProviderContainer container;
    late _FakeDashboardRepository fakeRepo;

    Future<DashboardNotifier> buildNotifier() async {
      final notifier = container.read(dashboardProvider.notifier);
      await container.read(dashboardProvider.future); // resolve build()
      return notifier;
    }

    void setUpContainer(_FakeDashboardRepository repo) {
      fakeRepo = repo;
      container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(repo),
        // Pin a band so build() takes the fetch path.
        selectedBandProvider.overrideWith(() => _StubBand()),
      ]);
      addTearDown(container.dispose);
    }

    test('merges and dedups older events by id', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: [_event(1, '2026-06-20')],
        olderBatches: [
          [_event(1, '2026-06-20'), _event(2, '2026-05-15')], // id 1 overlaps
        ],
      ));
      final notifier = await buildNotifier();

      await notifier.loadOlder();

      final state = container.read(dashboardProvider).value!;
      final ids = state.events.map((e) => e.id).toList()..sort();
      expect(ids, [1, 2], reason: 'duplicate id 1 must not be added twice');
    });

    test('loadedFrom decrements by 30 days per fetch', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: [
          [_event(2, '2026-05-15')],
        ],
      ));
      final notifier = await buildNotifier();
      final before = container.read(dashboardProvider).value!.loadedFrom;

      await notifier.loadOlder();

      final after = container.read(dashboardProvider).value!.loadedFrom;
      expect(before.difference(after).inDays, 30);
    });

    test('sets hasReachedStart when a fetch returns no events', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: const [], // first fetch returns empty
      ));
      final notifier = await buildNotifier();

      await notifier.loadOlder();

      final state = container.read(dashboardProvider).value!;
      expect(state.hasReachedStart, isTrue);
    });

    test('does not fetch again once hasReachedStart is set', () async {
      setUpContainer(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: const [],
      ));
      final notifier = await buildNotifier();

      await notifier.loadOlder(); // sets hasReachedStart
      await notifier.loadOlder(); // must be a no-op

      expect(fakeRepo.requestedBeforeDates.length, 1);
    });
  });
```

Add a stub band notifier near the fakes (matches `selectedBandProvider`'s type — it exposes a `Future<int?>`; confirm the exact notifier base class in `selected_band_provider.dart` and mirror it):

```dart
// selectedBandProvider is AsyncNotifierProvider<SelectedBandNotifier, int?>
// (confirmed selected_band_provider.dart:4,28-29). Override build() to pin a band.
class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 10;
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/dashboard/dashboard_provider_test.dart`
Expected: FAIL — `loadOlder` is not defined on `DashboardNotifier`.

- [ ] **Step 3: Implement `loadOlder()`**

In `lib/features/dashboard/providers/dashboard_provider.dart`, add this method to `DashboardNotifier` (after `refresh()`):

```dart
  /// Fetches the next-older 30-day window of events and merges them into the
  /// current state. Idempotent and self-guarding:
  /// - no-op while a fetch is in flight ([DashboardState.isLoadingOlder]),
  /// - no-op once history is exhausted ([DashboardState.hasReachedStart]),
  /// - merges by event id so overlapping day boundaries never duplicate.
  /// [loadedFrom] only ever moves backward (by 30 days per successful fetch).
  Future<void> loadOlder() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.isLoadingOlder || current.hasReachedStart) return;

    state = AsyncValue.data(current.copyWith(isLoadingOlder: true));

    try {
      final repo = ref.read(dashboardRepositoryProvider);
      final older = await repo.loadOlderEvents(current.loadedFrom.toIso8601String());

      final existingIds = current.events.map((e) => e.id).toSet();
      final merged = [
        ...current.events,
        ...older.where((e) => !existingIds.contains(e.id)),
      ];

      state = AsyncValue.data(current.copyWith(
        events: merged,
        loadedFrom: current.loadedFrom.subtract(const Duration(days: 30)),
        isLoadingOlder: false,
        hasReachedStart: older.isEmpty,
      ));
    } catch (_) {
      // On error, clear the in-flight flag so the user can retry; keep events.
      state = AsyncValue.data(
        (state.valueOrNull ?? current).copyWith(isLoadingOlder: false),
      );
    }
  }
```

> NOTE: `EventSummary` exposes an `id` (int) field — confirmed in `event_summary.dart`. If ids can be null/zero for some sources, dedup still holds because the set comparison is by value.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/dashboard/dashboard_provider_test.dart`
Expected: PASS (all tests from Task 4 + the 4 new `loadOlder` tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/providers/dashboard_provider.dart test/features/dashboard/dashboard_provider_test.dart
git commit -m "feat(dashboard): loadOlder merges/dedups older events with guards"
```

---

## Task 6: Frontend — watermark-triggered fetch on swipe + loading indicator

**Files:**
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart`
- Test: `test/features/dashboard/dashboard_provider_test.dart` (navigation-logic tests)

The screen wiring (`onPageChanged`) is thin; the testable logic — "should I fetch for this focused month, and loop until covered" — is extracted into a pure helper on the notifier so it can be unit-tested without a widget.

- [ ] **Step 1: Write the failing navigation tests**

Add this group to `test/features/dashboard/dashboard_provider_test.dart`. It exercises `ensureMonthLoaded`, the loop helper the screen will call.

```dart
  group('DashboardNotifier.ensureMonthLoaded (watermark trigger)', () {
    late ProviderContainer container;
    late _FakeDashboardRepository fakeRepo;

    Future<DashboardNotifier> build(_FakeDashboardRepository repo) async {
      fakeRepo = repo;
      container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(repo),
        selectedBandProvider.overrideWith(() => _StubBand()),
      ]);
      addTearDown(container.dispose);
      final notifier = container.read(dashboardProvider.notifier);
      await container.read(dashboardProvider.future);
      return notifier;
    }

    test('forward-then-back within loaded range fetches nothing', () async {
      final notifier = await build(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: [
          [_event(2, '2026-05-15')],
        ],
      ));
      final loadedFrom = container.read(dashboardProvider).value!.loadedFrom;

      // Focus a month AFTER loadedFrom (forward) — no fetch.
      await notifier.ensureMonthLoaded(
        DateTime(loadedFrom.year, loadedFrom.month + 2, 1),
      );
      // Focus a month at/after loadedFrom (already covered) — no fetch.
      await notifier.ensureMonthLoaded(
        DateTime(loadedFrom.year, loadedFrom.month, 1),
      );

      expect(fakeRepo.requestedBeforeDates, isEmpty);
    });

    test('two-back then one-forward fetches each chunk exactly once', () async {
      final notifier = await build(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: [
          [_event(2, '2026-05-15')],
          [_event(3, '2026-04-15')],
        ],
      ));
      final loadedFrom = container.read(dashboardProvider).value!.loadedFrom;

      // Jump ~2 months before the watermark — loop fetches until covered.
      await notifier.ensureMonthLoaded(
        DateTime(loadedFrom.year, loadedFrom.month - 2, 1),
      );
      final fetchesAfterBack = fakeRepo.requestedBeforeDates.length;
      expect(fetchesAfterBack, greaterThanOrEqualTo(2));

      // Now go one month forward — already covered, no new fetch.
      await notifier.ensureMonthLoaded(
        DateTime(loadedFrom.year, loadedFrom.month - 1, 1),
      );
      expect(fakeRepo.requestedBeforeDates.length, fetchesAfterBack);

      // before_dates are strictly decreasing (only ever marching backward).
      for (var i = 1; i < fakeRepo.requestedBeforeDates.length; i++) {
        final prev = DateTime.parse(fakeRepo.requestedBeforeDates[i - 1]);
        final curr = DateTime.parse(fakeRepo.requestedBeforeDates[i]);
        expect(curr.isBefore(prev), isTrue);
      }
    });

    test('stops looping when hasReachedStart even if month not covered', () async {
      final notifier = await build(_FakeDashboardRepository(
        initialEvents: const [],
        olderBatches: const [], // first fetch is empty → start reached
      ));
      final loadedFrom = container.read(dashboardProvider).value!.loadedFrom;

      // Ask for a month a year back; history is empty so it must not loop forever.
      await notifier.ensureMonthLoaded(
        DateTime(loadedFrom.year - 1, loadedFrom.month, 1),
      );

      expect(fakeRepo.requestedBeforeDates.length, 1);
      expect(container.read(dashboardProvider).value!.hasReachedStart, isTrue);
    });
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/dashboard/dashboard_provider_test.dart`
Expected: FAIL — `ensureMonthLoaded` not defined.

- [ ] **Step 3: Implement `ensureMonthLoaded()`**

In `dashboard_provider.dart`, add to `DashboardNotifier` (after `loadOlder()`):

```dart
  /// Ensures events for [focusedDay]'s month are loaded, fetching older chunks
  /// as needed. Fetches ONLY when the focused month's first day is strictly
  /// before the [DashboardState.loadedFrom] watermark — so forward navigation,
  /// or returning into an already-loaded range, never triggers a fetch. Loops
  /// to cover multi-month jumps, stopping when covered or history is exhausted.
  Future<void> ensureMonthLoaded(DateTime focusedDay) async {
    final monthStart = DateTime(focusedDay.year, focusedDay.month, 1);

    while (true) {
      final current = state.valueOrNull;
      if (current == null) return;
      if (current.hasReachedStart) return;
      if (!monthStart.isBefore(current.loadedFrom)) return; // already covered

      final fromBefore = current.loadedFrom;
      await loadOlder();

      final after = state.valueOrNull;
      // Guard against non-progress (e.g. an errored fetch left loadedFrom put):
      // if the watermark didn't move and start wasn't reached, stop to avoid a
      // hot loop. The next swipe can retry.
      if (after == null) return;
      if (after.hasReachedStart) return;
      if (!after.loadedFrom.isBefore(fromBefore)) return;
    }
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/dashboard/dashboard_provider_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Wire the screen's `onPageChanged` to call it**

In `lib/features/dashboard/screens/dashboard_screen.dart`, update the `onPageChanged` callback (lines ~135–140) to trigger the fetch:

```dart
                  onPageChanged: (focused) {
                    setState(() {
                      _focusedDay = focused;
                      _selectedDay = null;
                    });
                    // Lazily pull older events if we swiped past the loaded range.
                    ref.read(dashboardProvider.notifier).ensureMonthLoaded(focused);
                  },
```

- [ ] **Step 6: Add a loading indicator while older events fetch**

In `dashboard_screen.dart`, the `_DashboardContent` widget receives state via `_DashboardScreenState.build`. Pass `isLoadingOlder` down and show a `CupertinoActivityIndicator`. In the `data: (state) => _DashboardContent(...)` call (line ~123), add:

```dart
                data: (state) => _DashboardContent(
                  events: state.events,
                  currentEvent: state.currentEvent,
                  isLoadingOlder: state.isLoadingOlder,
                  focusedDay: _focusedDay,
                  selectedDay: _selectedDay,
```

Then in the `_DashboardContent` class, add the field and constructor param (near the other fields, around line 178):

```dart
  final bool isLoadingOlder;
```
```dart
    required this.isLoadingOlder,
```

And in `_DashboardContent.build`, render a small indicator above the event list when `isLoadingOlder` is true. Locate the `SliverList`/event-list section (around line 288 where the calendar is placed) and insert, just before the event list items:

```dart
            if (isLoadingOlder)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CupertinoActivityIndicator()),
              ),
```

> NOTE: exact insertion depends on whether the list is a `SliverList` (use a `SliverToBoxAdapter` wrapper) or a `Column` (use the `Padding` directly). Match the surrounding widget type. `flutter-ux-developer` may refine placement; functionally it just needs to be visible during `isLoadingOlder`.

- [ ] **Step 7: Verify analyze + full dashboard tests pass**

Run: `flutter analyze lib/features/dashboard/ && flutter test test/features/dashboard/`
Expected: "No issues found!" then all tests PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/features/dashboard/screens/dashboard_screen.dart lib/features/dashboard/providers/dashboard_provider.dart test/features/dashboard/dashboard_provider_test.dart
git commit -m "feat(dashboard): lazy-load older events on calendar swipe-back"
```

---

## Final verification

- [ ] **Backend:** from `/home/eddie/github/TTS`, run `docker compose exec app php artisan test --filter=DashboardTest` — all green.
- [ ] **Frontend:** from `tts_bandmate`, run `flutter analyze` (no issues) and `flutter test test/features/dashboard/` (all green).
- [ ] **Manual smoke (optional):** run the app against staging, open the dashboard, confirm the past ~30 days show, swipe back a few months, confirm older events appear and the spinner shows briefly; swipe forward/back within range and confirm no extra network calls (check logs).
  - **Gated on backend deploy:** staging does NOT auto-deploy while the backend PR is a draft. The `load-older` endpoint won't exist on staging until the TTS backend PR is marked ready-for-review and merged. Until then this smoke step will 404 — run it only after the backend PR is merged. (Unit/feature tests on both sides are unaffected.)
