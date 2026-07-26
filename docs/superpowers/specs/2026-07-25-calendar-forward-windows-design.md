# Calendar Forward Windows + Infinite Rehearsal Rendering — Design

**Date:** 2026-07-25
**Status:** Approved
**Repos:** `tts_bandmate` (Flutter, base `main`) + `TTS` (Laravel, base `staging`)

## Problem

Rehearsal schedules are recurring rules, but the mobile app only renders them
~8 weeks out, and the calendar cannot browse past now+365d even though some
bookings extend 3+ years into the future.

Root causes:

1. `RehearsalScheduleService::generateUpcomingRehearsals()` defaults its end
   date to `start + 12 weeks`. The mobile `DashboardController::index` calls
   `getEvents(now − 30d)` with no `beforeDate`, so virtual rehearsals stop
   ~54 days out while real events are unbounded.
2. The Flutter calendar caps `lastDay` at now+365d and has no forward
   lazy-fetch (only `loadOlder` for history).
3. The Rehearsals tab endpoint returns only materialized `Rehearsal` rows
   within 60 days — never virtual occurrences.

## Approach (chosen: backend windowed forward-fetch)

Mirror the existing `loadOlder` pattern with a forward counterpart. Recurrence
logic stays server-side in one place; the same windowed generation powers both
the calendar and the Rehearsals tab. Client-side occurrence generation in Dart
was rejected (recurrence-logic drift across languages; doesn't help far-future
bookings). A fixed bigger horizon was rejected (the wall just moves).

## 1. Backend — calendar forward windows

**New endpoint** `GET /api/mobile/dashboard/newer?after_date=Y-m-d&before_date=Y-m-d`
in `Api/Mobile/DashboardController`, mirroring `loadOlder`:

- `Auth::setUser($request->user())` (Sanctum guard binding, same as existing).
- Calls `(new UserEventsService())->getEvents($afterDate, $beforeDate)` —
  virtual rehearsals are already generated correctly for any bounded window.
- Formats via `DashboardFormatter::formatEvents` with unread counts, same as
  `loadOlder`. Response shape: `{ "events": [...] }`.
- Both params required; `before_date` must be after `after_date`.

**Initial payload forward-bounded, opt-in.** The app sends `?to=Y-m-d`
(now+90d) on `GET /api/mobile/dashboard`. When `to` is present the backend
passes it as `beforeDate`; when absent, behavior is unchanged (unbounded real
events, 12-week virtuals). Old app versions see no change.

**Jump-to-month in one request.** The client passes
`before_date = end of the focused month`, not a fixed step — swiping from
today to 2029 is one fetch covering the whole gap.

**No "reached end" concept.** An empty forward window proves nothing (a
booking can sit 3 years out with nothing in between). The client never stops
fetching on empty results; the browse cap is the calendar's `lastDay`
(now + 5 years).

## 2. Backend — Rehearsals tab

`RehearsalsController::schedules` gains two opt-in query params (default
response stays byte-compatible for old clients):

- `include_virtual=1` — merge virtual occurrences into `upcoming_rehearsals`
  via `RehearsalScheduleService`. The generator already skips dates with
  materialized rehearsals, so a cancelled real rehearsal shows as itself (with
  cancelled styling), never as a duplicate virtual. Virtual items carry
  `is_virtual: true` and key `virtual-rehearsal-{scheduleId}-{date}`; the
  existing `GET /api/mobile/rehearsals/by-key/{key}` endpoint materializes
  them on tap.
- `until=Y-m-d` — extends the window past the 60-day default (applies to both
  materialized and virtual occurrences). Load-more = re-request with a larger
  `until`; the client replaces the list wholesale (idempotent, no merge).

**`recurrence_label`** — a new server-formatted string on each schedule
("Every Tuesday at 7:00 PM", "Weekdays", "1st and 3rd Monday at 7:00 PM",
"Monthly on the 15th", "Custom schedule"), produced by a small unit-tested
formatter reading `frequency`, `selected_days`, `day_of_week` (legacy),
`monthly_pattern`, `day_of_month`, `monthly_weekday`, `default_time`.

## 3. Flutter — calendar

`DashboardState` gains:

- `loadedTo` watermark (symmetric with `loadedFrom`; only ever moves forward)
- `isLoadingNewer` in-flight guard
- **no** `hasReachedEnd` (future is unbounded within `lastDay`)

`DashboardNotifier`:

- `loadNewer(DateTime to)` — fetches `[loadedTo, to]` from the new endpoint,
  merges, advances `loadedTo`.
- `ensureMonthLoaded` gets a forward counterpart: focused month end past
  `loadedTo` → one `loadNewer(to: monthEnd)` call.
- Merge dedup: by `id` when present, by `key` for null-id events (virtual
  rehearsals) — extends the existing null-id-safe merge in `loadOlder`.
- `refresh()` resets both watermarks.
- Initial fetch sends `to = now + 90d`.

`dashboard_screen.dart`: `lastDay` changes from now+365d to now+5y.

## 4. Flutter — Rehearsals tab

Each schedule card shows:

- `recurrence_label` as the headline (conveys "infinite" honestly),
- merged upcoming list (server-merged virtual + real; virtuals tap through
  the existing by-key route),
- "Show more" button: bumps `until` by 90 days and refetches, replacing the
  list.

Repository/provider: `getSchedules` gains `until` + `include_virtual`
arguments; model gains `recurrenceLabel` and per-occurrence `isVirtual`/`key`.

## 5. Edge cases

- Inactive schedules: rule label shown, no occurrences (generator filters
  `active = true`).
- `custom` frequency: no virtuals by design — label reads "Custom schedule",
  list shows materialized only.
- Sub-only users: `getSubEvents` already honors `beforeDate`; no change.
- Timezones: dates remain naive date-strings, times naive — unchanged.
- Backward compatibility: every backend change is opt-in via query param;
  default responses are unchanged for old app versions.

## 6. Testing

Backend (feature tests, run in Docker app container):

- `dashboard/newer`: virtuals generated inside the window only; band scoping;
  sub-only user path; validation of params.
- `rehearsal-schedules` with `include_virtual`/`until`: merge correctness,
  materialized-date suppression (incl. cancelled), window bounds.
- Recurrence-label formatter: unit test per frequency type + legacy
  `day_of_week` fallback.

Flutter (provider tests, pinned clocks — no time-bomb dates):

- `loadNewer` merge/watermark/no-dup (id and key dedup paths).
- Forward `ensureMonthLoaded`: multi-year jump issues a single fetch.
- `refresh()` watermark reset.
- Rehearsals provider: `until` growth and list replacement.

## Branches

- TTS: `feat/calendar-forward-windows` → PR base `staging`
- tts_bandmate: `feat/calendar-forward-windows` → PR base `main`
