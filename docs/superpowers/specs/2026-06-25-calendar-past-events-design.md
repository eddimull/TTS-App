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
- After updating `_focusedDay`, if the focused month is at or before `loadedFrom`'s month, call `ref.read(dashboardProvider.notifier).loadOlder()`.
- `loadOlder()` is safe to call repeatedly (guards prevent overlap), so a loop / repeated invocation can cover multi-month jumps until `loadedFrom` covers the focused month or `hasReachedStart` is true.

### 4. Loading feedback
While `isLoadingOlder` is true, show a subtle `CupertinoActivityIndicator` in the event-list header region when the focused month has no loaded events yet. Placement to be refined during implementation (flutter-ux-developer).

## Data flow

```
swipe to older month
  → onPageChanged updates _focusedDay
  → if focusedMonth <= loadedFrom: notifier.loadOlder()
      → repo.loadOlderEvents(loadedFrom) → GET /api/mobile/dashboard/load-older?before_date=
      → merge + dedup by id, loadedFrom -= 30d, hasReachedStart if empty
  → calendar markers + event list re-render over the larger event set
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
- Follows the existing `ProviderContainer` + fake-repo pattern.

## Out of scope
- Changing the web feed dashboard (untouched).
- Forward (future) pagination — future events already load fully.
- Configurable window sizes; 30 days is fixed to match the web pattern.
