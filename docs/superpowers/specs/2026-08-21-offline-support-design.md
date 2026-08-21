# Offline Support — Design Spec

Date: 2026-08-21
Status: Approved design, pending implementation plan
Repo: tts_bandmate (Flutter app)

## Problem

The moment a device goes offline, the app degrades badly:

- Cold start offline: the auth → band-gate → dashboard chain serializes behind a
  10s Dio connect timeout, showing a bare spinner with no offline messaging,
  then an error screen containing a raw `DioException` dump.
- Warm app offline: `DashboardNotifier.refresh()` sets
  `state = const AsyncValue.loading()` before fetching, so any pull-to-refresh,
  realtime broadcast, or `CacheInvalidator` call while offline **discards data
  already on screen** and replaces it with a spinner, then an error. This is the
  reported "forever loading homepage".
- No repository or provider caches data (one exception: the bookings window),
  so there is nothing to fall back to.
- `connectivityProvider` only drives a cosmetic banner. It is never seeded
  (`null` until the first change event, treated as online) and nothing
  revalidates when connectivity returns.

## Goals

- The app is usable offline for **viewing** previously loaded information.
- Data already on screen is never discarded by a failed refresh.
- Offline failures show a friendly "You're offline" message, never a raw
  exception dump.
- Returning online revalidates stale data automatically.

## Non-goals (explicit)

- **No offline writes / mutation queue.** Read-only offline. Writes fail fast
  with the friendly offline message. Queued sync can be a later phase.
- No local database (drift/sqflite/hive). No new dependencies.
- No per-screen "last updated" timestamps — the existing offline banner is the
  staleness signal.
- Live setlist **controls** (next/skip/react — server/Pusher driven) stay
  online-only; only viewing the cached song list works offline.

## Approach

Generalize the stale-while-revalidate (SWR) pattern already proven in
`bookings_window_provider.dart` + `BookingsCacheStorage`: raw API JSON cached
in shared_preferences, painted instantly on build, revalidated in the
background, cached data kept on any network error.

Rejected alternatives:
- `dio_cache_interceptor` (HTTP-layer cache): new deps, `X-Band-ID` key
  complications, caches indiscriminately, and does not fix the
  discard-on-refresh bug — the provider work is needed regardless.
- Local DB as source of truth: a data-layer rewrite for a read-only-offline
  requirement. YAGNI.

## Components

### 1. `lib/shared/cache/api_cache_storage.dart` — shared JSON cache

Generalizes `BookingsCacheStorage`. Backed by shared_preferences.

- Stores **raw API JSON** — models have no `toJson()`; cached data re-enters
  through the same `Model.fromJson` path used for live responses.
- Key: `cache_v1:<bandId>:<logical-name>`
  (`dashboard`, `events:<params>`, `event:<key>`, `setlist_session:<eventKey>`,
  `booking:<id>`).
- Value: `{"savedAt": "<ISO8601>", "payload": <raw JSON>}`.
- API: `Future<CachedEntry?> read(key)`, `Future<void> write(key, json)`,
  `Future<void> clearBand(bandId)`, `Future<void> clearAll()`.
- `clearBand`/`clearAll` are called on band switch and logout so a user never
  sees another band's (or another user's) cached data.

### 2. `lib/shared/cache/swr.dart` — reusable SWR helper

A small helper function/mixin used inside each wired notifier — not a
base-class migration; existing hand-rolled notifiers keep their shape.

Behavior in `build()`:
1. Read cache. On hit: return cached models immediately and schedule a
   deferred revalidation via `Future(() => ...)` — the same deferral bookings
   uses so `build()`'s return does not overwrite the revalidation's `state =`.
2. On miss: fetch from network normally.

Behavior on revalidate (also used by `refresh()`):
- Fetch → on success: update state and write cache.
- On `DioException` of connection type: **keep current state silently**
  (mirror `BookingsWindowNotifier._revalidate`).
- On other errors (4xx/5xx with a response): surface the error only if there
  is no data on screen; otherwise keep data.
- When `connectivityProvider` reports offline, skip the network attempt
  entirely — no 10s timeout spinner.

### 3. Wired providers (priority screens)

| Provider | Cache key | Notes |
|---|---|---|
| `dashboardProvider` | `dashboard` | fixes the reported bug |
| `bandEventsProvider` | `events:<params>` | event list |
| `eventDetailProvider` | `event:<key>` | converted to `AsyncNotifierProvider.family` so it can revalidate in place |
| live setlist `getSession` fetch | `setlist_session:<eventKey>` | view-only offline |
| bookings detail | `booking:<id>` | window/list already cached |

Repositories stay thin Dio callers. Caching happens at the provider layer,
which needs the raw response JSON: wired repo methods return/expose raw JSON
alongside models (the precedent bookings already set).

### 4. Refresh semantics — never discard on-screen data

- `DashboardNotifier.refresh()` (and the same pattern in every wired provider)
  stops resetting to `AsyncValue.loading()`. Refresh = revalidate in place.
- `CacheInvalidator` and realtime (Pusher) triggered refreshes therefore
  become offline-safe automatically.

### 5. Connectivity

- Seed `connectivityProvider` with an initial
  `Connectivity().checkConnectivity()` so the state is correct before the
  first change event.
- On the offline→online edge (already detected in `app_scaffold.dart`),
  trigger revalidation of the wired providers (via `CacheInvalidator`).
- Known limitation (accepted): `connectivity_plus` reports link presence, not
  reachability; a captive portal reads as online. The keep-data-on-error rule
  covers that case anyway.

### 6. Error UX

- `ErrorView.friendlyMessage` gains a branch for
  `DioExceptionType.connectionError` / `connectionTimeout` / `unknown` with a
  `SocketException` cause → "You're offline. Check your connection and try
  again." No more raw `DioException` text.
- Cold start fully offline with an empty cache → friendly offline `ErrorView`
  with Retry (not a spinner).
- Writes offline: no new blocking layer; existing failure paths now render the
  friendly message wherever `friendlyMessage` is used.

## Data flow (warm offline example)

1. App resumes offline; realtime or `CacheInvalidator` calls `refresh()`.
2. Notifier keeps current state (no loading reset), sees offline via
   `connectivityProvider`, skips the network attempt.
3. UI keeps showing data; the existing offline banner communicates staleness.
4. Device comes back online → offline→online edge fires → wired providers
   revalidate → fresh data + cache write.

## Testing

Unit tests (`ProviderContainer` + fakes, existing pattern):
- Cache hit paints instantly, then revalidates and updates state + cache.
- Connection error during revalidate keeps cached state (no error state).
- `refresh()` never transitions to loading when data is present.
- Band switch / logout clears cached entries for that band / all.
- `ApiCacheStorage` round-trips payloads and timestamps.
- `friendlyMessage` maps connection-type errors to the offline message.
- Offline state skips network attempts.

Manual on-device verification:
- Airplane-mode warm app: dashboard/events/setlist/booking data stays visible;
  pull-to-refresh does not blank the screen.
- Airplane-mode cold start with warm cache: screens paint from cache.
- Airplane-mode cold start, empty cache: friendly offline error + Retry.
- Reconnect: data revalidates without user action.
