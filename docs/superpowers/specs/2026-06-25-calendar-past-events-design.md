# Calendar Past Events — Design

**Date:** 2026-06-25
**Branch:** `feat/calendar-past-events`
**Repos:** `tts_bandmate` (Flutter) + `TTS` (Laravel backend)

## Problem

The mobile dashboard calendar currently shows only events from *now − 72 hours* forward. This limit comes from the Laravel `UserEventsService::getEvents()` default (`Carbon::now()->subHours(72)`), which the mobile dashboard endpoint inherits because it passes no date range. The forward-only behavior exists for the **web** app, whose dashboard is a feed view rather than a calendar.

On mobile, the dashboard *is* a month calendar (`table_calendar`), so users naturally want to look at recent past events. We want:

1. The **past 30 days** of events visible on initial load.
2. Swiping back to months before the loaded range **lazily fetches older events**, 30 days at a time, reusing the web app's existing `loadOlderEvents` pattern.

## Existing behavior (reference)

- **Web** already has infinite-scroll-back via `DashboardController::loadOlderEvents()` (`routes/web.php:32` → `dashboard.load-older`). It takes `before_date`, computes `afterDate = before − 30 days`, and calls `getEvents($afterDate, $beforeDate)`.
- **`UserEventsService::getEvents($afterDate, $beforeDate, $limit)`** already accepts an explicit date range and handles sub-only vs. band-access visibility. The mobile controller simply never passes a range.
- **Mobile dashboard** (`Api\Mobile\DashboardController::index`) runs results through `DashboardFormatter::formatEvents()` to produce the normalized shape the Flutter `EventSummary.fromJson` expects.

## Backend design (Laravel — `/home/eddie/github/TTS`)

### 1. Widen the initial window
In `app/Http/Controllers/Api/Mobile/DashboardController::index()`, pass an explicit `afterDate` of `Carbon::now()->subDays(30)` to `getEvents()`. This replaces the inherited 72-hour default and yields the past month on first load.

### 2. New mobile "load older" endpoint
Add `loadOlder(Request $request)` to the mobile `DashboardController`, mirroring the web `loadOlderEvents`:

- Read `before_date` (ISO date). If absent, return `{ events: [] }`.
- `afterDate = Carbon::parse(before_date)->subDays(30)`.
- `$events = (new UserEventsService())->getEvents($afterDate, $beforeDate);`
- Normalize through the **same `DashboardFormatter`** the index uses, so mobile receives the identical event shape.
- Return `{ events: [...] }`.

Route (under same auth middleware as `mobile.dashboard`):
```php
Route::get('/dashboard/load-older', [DashboardController::class, 'loadOlder'])
    ->name('mobile.dashboard.load-older');
```

Visibility (sub vs. band access) is inherited from `getEvents()` — no extra handling needed.

## Frontend design (Flutter — `tts_bandmate`)

### 1. Repository
`lib/features/dashboard/data/dashboard_repository.dart`:
```dart
Future<List<EventSummary>> loadOlderEvents(String beforeDate)
```
GETs `/api/mobile/dashboard/load-older?before_date=<iso>`, parses `events` into `List<EventSummary>` reusing the same parsing as `getDashboard()`.

New endpoint constant in `lib/core/network/api_endpoints.dart`:
```dart
static const String mobileDashboardLoadOlder = '/api/mobile/dashboard/load-older';
```

### 2. Provider / state
`lib/features/dashboard/providers/dashboard_provider.dart`:

`DashboardState` gains:
- `DateTime loadedFrom` — earliest date currently loaded. Initialized to `now − 30d` on first build.
- `bool isLoadingOlder` — guards against duplicate fetches; drives loading UI.
- `bool hasReachedStart` — set when a fetch returns zero events; stops further back-fetching.

`DashboardNotifier.loadOlder()`:
- Return early if `isLoadingOlder` or `hasReachedStart`.
- Set `isLoadingOlder = true`.
- Call `repository.loadOlderEvents(loadedFrom.toIso8601String())`.
- **Merge + dedup** returned events into the existing list keyed by event `id` (ranges overlap by a day boundary).
- `loadedFrom = loadedFrom − 30d`.
- If the response was empty, set `hasReachedStart = true`.
- Set `isLoadingOlder = false`.

### 3. Screen
`lib/features/dashboard/screens/dashboard_screen.dart`, in the calendar's `onPageChanged`:

The trigger is a **strict watermark** comparison, not a month-equality check. `loadedFrom` is the genuine earliest-loaded date and only ever moves backward. The first day of the focused month must be **strictly before** `loadedFrom` for a fetch to fire:

```
focusedMonthFirstDay = DateTime(focusedDay.year, focusedDay.month, 1)
while (focusedMonthFirstDay.isBefore(loadedFrom) && !hasReachedStart) {
  await notifier.loadOlder();   // fetches before_date = loadedFrom, then loadedFrom -= 30d
}
```

Why strict `<` against the watermark (and not `<=` against the month):
- **Going forward never fetches** — a later month's first day is never before `loadedFrom`.
- **Going back into already-loaded range never fetches** — those months are `>= loadedFrom`, so the condition is false.
- **Only crossing past the real frontier fetches**, and each `loadOlder()` advances `loadedFrom` strictly backward, so a chunk is requested exactly once.

`loadOlder()` always fetches `before_date = loadedFrom`. The loop handles multi-month jumps (e.g. swiping fast / jumping several months back) by repeating until the watermark covers the focused month or `hasReachedStart` is true. The in-flight guard (`isLoadingOlder`) plus `await` keeps overlapping calls from racing.

**Avoided logic trap:** with the earlier `<=`-against-month design, "two back, one forward" or "forward then back within loaded range" would re-fire `loadOlder()` on every swipe — re-requesting a chunk relative to a stale `loadedFrom` (the dedup hid duplicate *data*, but the network round-trip was wasted every time). The strict-watermark trigger eliminates this.

### 4. Loading feedback
While `isLoadingOlder` is true, show a subtle `CupertinoActivityIndicator` in the event-list header region when the focused month has no loaded events yet. Placement to be refined during implementation (flutter-ux-developer).

## Data flow

```
swipe to a month
  → onPageChanged updates _focusedDay
  → while focusedMonthFirstDay < loadedFrom AND !hasReachedStart:
      notifier.loadOlder()
        → repo.loadOlderEvents(loadedFrom) → GET /api/mobile/dashboard/load-older?before_date=
        → merge + dedup by id, loadedFrom -= 30d, hasReachedStart if empty
  → calendar markers + event list re-render over the larger event set

(forward navigation, or back into already-loaded range, never fetches:
 focusedMonthFirstDay is not strictly before the loadedFrom watermark)
```

## Testing

### Backend (Laravel)
- Feature test for `GET /api/mobile/dashboard/load-older`: returns events within the requested past 30-day window; respects sub-only vs. band visibility; empty `before_date` returns `{ events: [] }`. Reuse existing mobile dashboard test fixtures.

### Frontend (Flutter)
- Unit test on `DashboardNotifier.loadOlder()` with a fake repository:
  - merge + dedup by id (no duplicate days when ranges overlap),
  - `loadedFrom` decrements by 30 days,
  - `hasReachedStart` set on empty response,
  - no double-fetch while `isLoadingOlder` is true.
- Watermark-trigger tests (the navigation logic, with a fake repo that counts calls):
  - **forward-then-back within loaded range fetches nothing** — after loading one chunk, focus a later month then return to an already-covered month; assert zero additional `loadOlderEvents` calls.
  - **two-back, one-forward fetches each chunk exactly once** — jump two months past the frontier (two chunks fetched), then one month forward (no fetch); assert `loadOlderEvents` called exactly twice with strictly-decreasing `before_date`.
  - **multi-month jump back loops until covered** — focus a month several chunks before `loadedFrom`; assert the loop fetches enough chunks for `loadedFrom` to cover it, stopping early if `hasReachedStart`.
- Follows the existing `ProviderContainer` + fake-repo pattern.

## Out of scope
- Changing the web feed dashboard (untouched).
- Forward (future) pagination — future events already load fully.
- Configurable window sizes; 30 days is fixed to match the web pattern.
