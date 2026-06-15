# Bookings — instant paint, disk cache, and silent revalidation

## Goal

Fix three perceived problems on the Bookings screen, in order of visibility:

1. **Visible content shift on open.** The list paints sorted-ascending (oldest
   booking in the window at index 0), then a post-frame callback jumps to the
   nearest-upcoming booking. The user sees the list "start at the beginning of
   time" and lurch forward. Eliminate the shift at its source by rendering the
   list already positioned at the nearest-upcoming booking.
2. **Full-screen spinner on every visit.** `bookingsWindowProvider` is in-memory
   only; the shell is a plain `ShellRoute`, so leaving the tab disposes the
   screen and a return triggers a full refetch with a blocking spinner. There is
   no cross-session cache, so cold start is also a blocking spinner. Persist the
   initial window to disk and paint it instantly.
3. **No background refresh.** Revisits are all-or-nothing (spinner → data).
   Adopt stale-while-revalidate: paint cached data immediately, then refresh in
   the background and swap in fresh data with no spinner.

This is a direct follow-up to `2026-05-03-bookings-windowed-loading-design.md`,
which listed "Cross-session caching of the loaded window" as out of scope.

## Out of scope

- Persisting `loadEarlier` / `loadLater` expansion slices. Only the initial
  window (3 months back, 9 months ahead) is cached. Expansions remain cheap
  on-scroll re-fetches.
- A TTL / staleness gate on the cache. `build()` always revalidates over the
  network regardless of cache age; the cost is one request.
- A visible "revalidating…" indicator. Background refresh is silent.
- Changing the shell to `StatefulShellRoute` / `IndexedStack`. The disk cache
  plus instant paint makes the in-session refetch a non-issue; keeping the shell
  as-is minimizes blast radius.
- Any backend change. The endpoint and response shape are unchanged.
- Adding `toJson` to `BookingSummary` and its nested models. The cache stores
  the raw API JSON maps instead (see Serialization).

## Fix 1 — Render already-positioned

`ScrollablePositionedList.builder` supports `initialScrollIndex` (and
`initialAlignment`), applied on first attach. Compute the nearest-upcoming
**header** index during build and pass it as `initialScrollIndex`, so the first
painted frame is already at the right place.

### Computation

In `_buildContent` (or a small helper), given `data.items` and
`data.monthHeaderIndex`:

1. Find the nearest-upcoming booking via the existing
   `findNearestUpcomingIndex(visibleAfterFilter, clock())` against
   `data.visibleAfterFilter`. (Use `clockProvider`, not `DateTime.now()`
   directly, for testability.)
2. Map that booking's month key to its header index in `monthHeaderIndex`.
3. That header index, **plus `_topSentinels`**, is `initialScrollIndex`.
4. If there is no upcoming booking, `initialScrollIndex` is the last header
   (most recent past month) — matching today's "nothing upcoming" behavior of
   leaving the chip on the latest month.

Seed `_selectedMonthKey` from the same computed month key so the chip strip
highlight matches the initial scroll position without waiting for the first
`_onItemPositionsChange`.

### Deletions

The jump apparatus is removed entirely:

- Methods: `_scheduleJumpToNearest`, `_attemptJump`, `_cancelInFlightJump`.
- Fields: `_hasJumpedToNearest`, `_jumpInFlight`, `_jumpGeneration`,
  `_pendingJumpRetries`, `_maxJumpRetries`.
- The `!_hasJumpedToNearest` gate in the `data:` builder.

### Preserved mechanisms

- **`loadEarlier` prepend anchor** (`_scrollAnchor` + its post-frame restore in
  the `data:` builder). `initialScrollIndex` only applies on first attach; after
  a prepend the existing anchor restoration keeps position. Unchanged.
- **Filter-change re-anchor.** A filter change rebuilds the list, so a freshly
  computed `initialScrollIndex` takes effect on the rebuilt
  `ScrollablePositionedList`. The `ref.listen<BookingsFilterState>` block that
  previously called `_scheduleJumpToNearest` is removed; recomputation in build
  replaces it. (Confirm during implementation that a filter change forces a new
  `ScrollablePositionedList` element so `initialScrollIndex` re-applies; if not,
  a `ValueKey` derived from the filter is added to force a fresh attach.)
- **Chip tap / chip highlight on scroll** (`_onMonthChipTap`,
  `_onItemPositionsChange`). Unchanged.

## Fix 2 — Persist the initial window to disk

### Storage wrapper

New `BookingsCacheStorage`, mirroring `RouteStorage`
(`lib/core/storage/route_storage.dart`): a thin `SharedPreferences` wrapper,
exposed via a provider and resolved in `main.dart` alongside `routeStorage`.

Location: `lib/features/bookings/data/bookings_cache_storage.dart`
(feature-local, since it serves only the bookings window).

Stored blob (single JSON string under one key, e.g. `bookings_window_cache`):

```json
{
  "from": "2026-03-01",
  "to": "2026-12-31",
  "cachedAt": 1718409600000,
  "bookings": [ /* raw API booking maps, verbatim */ ]
}
```

API:

- `BookingsWindowCache? read()` — returns the parsed blob or null. Tolerates
  malformed JSON (returns null, clears the key).
- `void write(BookingsWindowCache cache)` — serializes and stores.
- `void clear()` — removes the key (used on logout — see Lifecycle).

`BookingsWindowCache` is a tiny value object: `from`, `to`, `cachedAt`
(`DateTime`), and `List<Map<String, dynamic>> rawBookings`.

### Serialization — raw JSON

`BookingSummary` has `fromJson` but no `toJson`, and neither do its nested
models (`BandSummary`, `EventSummary`, `BookingContact`). Rather than author
`toJson` across all of them, the cache stores the **raw response maps**.

The repository gains a way to surface the raw list. Preferred shape: a method
`getAllUserBookingsRaw(...)` returning
`({ List<BookingSummary> parsed, List<Map<String, dynamic>> raw })`, or
`getAllUserBookings` is refactored to return both. The notifier uses `parsed`
for state and persists `raw`. On cache read, `raw` maps go back through
`BookingSummary.fromJson` — the same path as a live response, so cached and live
data are structurally identical and forward-compatible.

### Notifier `build()`

`BookingsWindowNotifier.build()` becomes:

1. Compute desired `from` / `to` (existing 3-back / 9-ahead math via
   `clockProvider`).
2. Read cache. If present, parse its `rawBookings` and return a `BookingsWindow`
   built from them **synchronously** (no network await), using the cached
   `from`/`to`. Then schedule a non-awaited `_revalidate()` (Fix 3).
3. If absent, fall back to today's behavior: `await` the network fetch (blocking
   spinner is correct for a true cold-empty cache), populate state, and write
   the result to cache.

The cache window need not exactly equal the desired window; cached `from`/`to`
are used as-is for the returned `BookingsWindow`, and revalidation immediately
re-fetches the canonical desired window and overwrites both state and cache.

## Fix 3 — Stale-while-revalidate

An `AsyncNotifier.build()` returns once, so it cannot both return cached data
and await the refresh. Instead:

- `build()` returns cached data immediately and calls `_revalidate()` **without
  awaiting** it.
- `_revalidate()` fetches the canonical desired window. On success it sets
  `state = AsyncData(freshWindow)` and writes the fresh raw list to cache. The
  UI swaps in place with no spinner (state was already `AsyncData`).
- On error `_revalidate()` keeps the cached data and swallows the error
  (matching the existing `loadEarlier`/`loadLater` "preserve prior window on
  transient blip" policy). No user-visible error when cached data is on screen.
- `_revalidate()` guards on `ref.mounted` before mutating state.

`loadEarlier`, `loadLater`, and `refresh()` are unchanged except that a
successful fresh full-window load (build's no-cache path and `_revalidate`)
writes through to the cache.

## Lifecycle / invalidation

- **Mutations.** `CacheInvalidator._invalidateBookingCollections` already calls
  `_ref.invalidate(bookingsWindowProvider)`, which re-runs `build()`. Because
  `build()` paints from cache then revalidates, a mutation shows stale data for
  a beat then refreshes — acceptable, and the mutation site's own optimistic
  flow is unaffected. No change needed here, but the disk cache is refreshed by
  the subsequent `_revalidate()`.
- **Logout.** The disk cache must be cleared on logout so a different user never
  sees the previous user's bookings. Wire `BookingsCacheStorage.clear()` into
  `AuthNotifier.logout()` (`lib/features/auth/providers/auth_provider.dart:137`),
  alongside the existing best-effort `routeStorage.clearLastRoute()` block
  (same try/catch-guarded pattern). This is a required, security-relevant step.

## Testing

Pin `clockProvider` in every date-sensitive test (no hardcoded "today" — per the
project's "avoid time-bomb date tests" guidance). Use an in-memory / fake
`SharedPreferences` (`SharedPreferences.setMockInitialValues`).

1. **`BookingsCacheStorage` round-trip.** write(blob) → read() equals input;
   malformed stored string → read() returns null and clears the key.
2. **`build()` cache-hit is synchronous.** With a seeded cache and a repo fake
   whose fetch never completes (or asserts not-called-before-return), `build()`
   resolves to the cached window without awaiting the network.
3. **Revalidate swaps fresh data.** Seed cache with list A; repo fake returns
   list B; after `build()` settles and `_revalidate()` runs, state holds B and
   the cache file holds B's raw maps.
4. **Revalidate error preserves cache.** Repo fake throws on revalidate; state
   stays at the cached window; no thrown error escapes.
5. **No-cache cold path.** Empty cache → `build()` awaits, returns the fetched
   window, and writes it to cache.
6. **`initialScrollIndex` computation.** Given a sorted list with a known
   nearest-upcoming booking and a pinned clock, the computed
   `initialScrollIndex` equals that booking's month-header index (plus
   sentinels). With no upcoming booking, it equals the last header index.

## Files touched

- `lib/features/bookings/providers/bookings_window_provider.dart` — cache read
  in `build()`, `_revalidate()`, write-through.
- `lib/features/bookings/data/bookings_cache_storage.dart` — **new** storage
  wrapper + `BookingsWindowCache` value object + provider.
- `lib/features/bookings/data/bookings_repository.dart` — surface raw maps from
  `getAllUserBookings`.
- `lib/features/bookings/screens/bookings_screen.dart` — `initialScrollIndex`
  computation; delete jump apparatus.
- `lib/main.dart` — resolve `bookingsCacheStorageProvider` override (mirror
  `routeStorage`).
- Logout path — call `BookingsCacheStorage.clear()`.
- `test/features/bookings/...` — tests above.
