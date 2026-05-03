# Bookings — windowed loading

## Goal

Replace the current "fetch every booking the user has, every load" behavior
of the Bookings screen with a windowed load: initial payload is a 12-month
slice (3 months back, 9 months forward), and additional 6-month chunks
auto-load as the user scrolls within ~10 items of either edge of the
loaded list. Bands with thousands of bookings then pay startup cost
proportional to ~12 months of bookings instead of all-time history.

## Out of scope

- Pull-to-refresh (was dropped in the prior styling pass; not reintroduced).
- Pagination of `BandBookingsParams` / `bandBookingsProvider` (per-band
  detail flows keep the existing year-based filter — bookings detail / form
  screens do not change).
- Cross-session caching of the loaded window (window resets every time the
  screen mounts).
- Partial-window invalidation on booking create/edit/delete. Mutations call
  the existing `refresh()` and reload the full window from scratch.
- Backend response-shape change. The endpoint still returns
  `{ "bookings": [...] }`. The "edge reached" signal is an empty array.

## Backend (Laravel)

### Endpoint changes

`GET /api/mobile/me/bookings` (handler: `BookingsController::indexForUser`,
`/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/BookingsController.php`)
gains two optional query parameters:

- `from` — `nullable|date_format:Y-m-d`. Earliest date, inclusive.
- `to` — `nullable|date_format:Y-m-d`. Latest date, inclusive.

When `from` is present: `$query->whereDate('date', '>=', $from)`.
When `to` is present: `$query->whereDate('date', '<=', $to)`.
Both compose with the existing `status` / `upcoming` / `year` params.

If both `from` and `to` are present and `from > to`, return 422.

The existing param surface is preserved for backwards compatibility — no
caller is forced to update.

### Backend tests

Extend the existing controller test (or create one if missing) at
`test/Feature/Api/Mobile/UserBookingsControllerTest.php`:

- `from` alone narrows the result.
- `to` alone narrows the result.
- `from + to` together narrow the result.
- `from > to` returns 422.
- No params still returns all bookings (backwards-compat guard).

## Client repository

`lib/features/bookings/data/bookings_repository.dart`:

`getAllUserBookings` gains two optional params:

```dart
Future<List<BookingSummary>> getAllUserBookings({
  String? status,
  bool upcomingOnly = false,
  int? year,
  DateTime? from,
  DateTime? to,
})
```

When `from` is non-null, send `from=YYYY-MM-DD`. When `to` is non-null,
send `to=YYYY-MM-DD`. Existing callers don't pass either and continue
to work unchanged.

### Repository tests

Extend `test/features/bookings/bookings_repository_user_bookings_test.dart`:

- Passing `from: DateTime(2026, 1, 1)` and `to: DateTime(2026, 6, 30)`
  produces the expected `from=2026-01-01&to=2026-06-30` query string.
- Passing only `from` sends only `from=...`.
- Passing only `to` sends only `to=...`.

## Client provider

Replace the parameterless `userBookingsProvider` with a stateful
notifier that owns the loaded window.

### Files

- New: `lib/features/bookings/providers/bookings_window_provider.dart`.
- Modify: `lib/features/bookings/providers/bookings_provider.dart` to
  remove the `userBookingsProvider` declaration (its replacement lives
  in the new file). The repository function and other providers stay.
- New: `lib/features/bookings/providers/clock_provider.dart` — a tiny
  `Provider<DateTime Function()>` so tests can pin "now" for the
  initial window math.

### Shape

```dart
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

  final DateTime from;                  // inclusive
  final DateTime to;                    // inclusive
  final List<BookingSummary> bookings;  // sorted ascending by date
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
  });
}

class BookingsWindowNotifier extends AsyncNotifier<BookingsWindow> {
  @override
  Future<BookingsWindow> build() async {
    final now = ref.read(clockProvider)();
    // 3 months back, 9 months forward — 12-month initial window,
    // forward-weighted to match the screen's "next upcoming" defaults.
    final from = DateTime(now.year, now.month - 3, 1);
    final to = DateTime(now.year, now.month + 10, 0); // last day of month + 9
    final repo = ref.read(bookingsRepositoryProvider);
    final bookings = await repo.getAllUserBookings(from: from, to: to);
    return BookingsWindow(
      from: from,
      to: to,
      bookings: _sortByDateAscending(bookings),
      reachedEarliest: false,
      reachedLatest: false,
      isLoadingEarlier: false,
      isLoadingLater: false,
    );
  }

  Future<void> loadEarlier() async { ... }
  Future<void> loadLater()   async { ... }
  Future<void> refresh()     async => ref.invalidateSelf();
}

final bookingsWindowProvider =
    AsyncNotifierProvider<BookingsWindowNotifier, BookingsWindow>(
  BookingsWindowNotifier.new,
);
```

### `loadEarlier` algorithm

1. Read current state. If `state.value` is null OR `value.isLoadingEarlier`
   is true OR `value.reachedEarliest` is true, return immediately.
2. Set `isLoadingEarlier = true` (via `state = AsyncData(value.copyWith(...))`).
3. Compute `newFrom = subtractMonths(current.from, 6)` and
   `newTo = subtractDays(current.from, 1)` (one day before the current
   window's earliest day so the ranges are disjoint).
4. Fetch via `repo.getAllUserBookings(from: newFrom, to: newTo)`.
5. If the result is empty, set `reachedEarliest = true` and leave
   `bookings` unchanged. Otherwise, prepend the (sorted) new bookings
   and advance `from = newFrom`.
6. Set `isLoadingEarlier = false`.

`loadLater` mirrors with `+ 6 months` and `reachedLatest` / `to`.

Both methods are concurrency-safe via the in-flight flag (step 1).
Errors during the fetch leave `isLoadingEarlier`/`isLoadingLater` false
and surface via `state = AsyncError(...)`. The screen continues to
render the previous window; a future scroll-edge will retry naturally.

### Provider tests

New file `test/features/bookings/providers/bookings_window_provider_test.dart`:

- Initial `build()` requests `from = today − 3mo` through `to = today + 9mo`
  (assert the `BookingsRepository` call's args using a stub repo).
- Use `clockProvider` override to pin "now" so the assertion is stable.
- `loadEarlier` requests `from = (current.from − 6mo)` through
  `to = (current.from − 1 day)` and prepends the result.
- `loadEarlier` with empty response sets `reachedEarliest = true` and
  leaves `bookings` unchanged.
- A second call to `loadEarlier` while `isLoadingEarlier` is true is a
  no-op (assert the repo isn't hit twice).
- `loadEarlier` after `reachedEarliest = true` is a no-op.
- Symmetric set for `loadLater`.

## Client screen

`lib/features/bookings/screens/bookings_screen.dart` consumes
`bookingsWindowProvider` instead of `userBookingsProvider`.

### Watch / listen surface changes

- `ref.watch(userBookingsProvider)` → `ref.watch(bookingsWindowProvider)`.
- The `bookingsAsync.when(data:)` builder receives `BookingsWindow`
  instead of `List<BookingSummary>`. The existing pipeline runs against
  `window.bookings` — no change to `_buildListData` / `_filteredSorted`
  / `_maybeJumpToNearest` signatures.
- The two `ref.listen` calls (`userBookingsProvider`,
  `bookingsFilterProvider`) re-target to `bookingsWindowProvider` and
  pass `window.bookings` through to `_filteredSorted`.

### Auto-load on scroll edge

Extend `_onItemPositionsChange` (the existing chip-highlight listener):

```dart
void _onItemPositionsChange() {
  final positions = _itemPositionsListener.itemPositions.value;
  if (positions.isEmpty) return;

  // ── existing chip-highlight logic ──

  // ── new: auto-load on scroll edge ──
  final window = ref.read(bookingsWindowProvider).value;
  if (window == null) return;
  final notifier = ref.read(bookingsWindowProvider.notifier);

  // Edge detection runs against the rendered (post-filter) item count
  // so a sparse filtered list still triggers expansion at its visual
  // edge instead of waiting for the underlying window's edge.
  final renderedCount = _renderedItemCount;
  if (renderedCount == 0) return;

  final firstIdx = positions.map((p) => p.index).reduce(min);
  final lastIdx = positions.map((p) => p.index).reduce(max);

  if (firstIdx <= 10 &&
      !window.reachedEarliest &&
      !window.isLoadingEarlier) {
    _captureScrollAnchor();
    notifier.loadEarlier();
  }
  if (lastIdx >= renderedCount - 10 &&
      !window.reachedLatest &&
      !window.isLoadingLater) {
    notifier.loadLater();
  }
}
```

`_renderedItemCount` is set in the `data:` builder when `_buildListData`
runs (it's already computed implicitly as `data.items.length` — store
it on the state so the listener can read it).

### Scroll-anchor on prepend (loadEarlier)

When the window prepends new items at the top, the user's currently-
visible content shifts down by some number of indices. To keep the
user's view anchored on the same booking they were looking at:

1. Just before calling `loadEarlier`, capture the state's "anchor":
   walk the visible positions from the topmost downward and find the
   first one whose `data.items[i]` is a `_CardItem` (skip `_HeaderItem`s
   — they don't carry a stable identity across rebuilds since the
   prepend may add new month headers). Store the anchor as
   `(int bookingId, double leadingEdge)` on the state, where
   `leadingEdge` is that position's `ItemPosition.itemLeadingEdge`. If
   no `_CardItem` is currently visible (e.g. only a sentinel spinner is
   on screen), don't set an anchor — the rebuild will land at the
   default position (top), which is acceptable since the user wasn't
   reading specific content anyway.
2. After `loadEarlier` completes and the rebuild runs, in the `data:`
   builder, if an anchor is set, look up the new `data.items` index
   that holds a `_CardItem` with matching `booking.id`. If found, call
   `_itemScrollController.jumpTo(index: newIdx + topSentinels, alignment: leadingEdge)`
   and clear the anchor. If not found (the booking somehow disappeared,
   e.g. concurrent delete), clear the anchor and leave the scroll
   wherever it is.

`ScrollablePositionedList`'s index-based API makes this clean — no
pixel arithmetic. The anchor only restores after `loadEarlier`; there's
no anchoring on `loadLater` because appending doesn't shift the user's
visible items.

### Loading affordance

When `window.isLoadingEarlier` is true, the `itemBuilder` renders a
small `CupertinoActivityIndicator` row at the very top of the list.
Mirror at the bottom for `isLoadingLater`. The spinners are NOT in
`data.items` — they are added by `itemBuilder` and accounted for in
`itemCount`.

**Index mapping.** Let `topSentinels = isLoadingEarlier ? 1 : 0` and
`bottomSentinels = isLoadingLater ? 1 : 0`. Then:

- `itemCount = data.items.length + topSentinels + bottomSentinels`.
- For a builder index `i`, the `data.items` index is `i - topSentinels`.
  When that's `< 0` or `>= data.items.length`, the builder returns a
  spinner.
- `_onItemPositionsChange` translates `ItemPosition.index` into a
  `data.items` index by subtracting `topSentinels` before doing the
  chip-highlight or edge-detection math. Indices that fall outside
  `[0, data.items.length)` after translation are ignored.
- `_itemScrollController.jumpTo(index: N)` calls (used by chip-tap and
  initial jump) operate on `data.items` indices and need to add
  `topSentinels` before passing to the controller.

Doing the translation in the listener (and at the two `jumpTo` call
sites) keeps `_buildListData` / `_monthHeaderIndex` simple — they
continue to ignore sentinels entirely.

### Initial jump-to-nearest behavior

Unchanged. The initial window includes today (it's centered between
3 months back and 9 months forward), so the nearest-upcoming booking
is almost always inside the initial window. If the user has zero
bookings in the next 9 months, the existing fallback behavior
(jump to the most-recent past booking) still works as long as that
past booking is in the initial 3-month lookback. If it's older than
that, the screen lands at the bottom of an empty-ish window — that's
acceptable since the user can scroll up and trigger `loadEarlier`.

## Filter / search interaction

Filter and search remain entirely client-side. No filter change
triggers a refetch. The screen filters `window.bookings` via the
existing `_filteredSorted` and `bookingMatchesQuery` helpers exactly
as today.

The "sparse filtered window" edge case (e.g. user filters to
"Confirmed only" and the loaded window has very few confirmed
bookings) is self-healing: edge detection runs on the rendered count,
so scrolling to the bottom of a short filtered list triggers
`loadLater`, the new chunk arrives, the filter re-applies, and more
items appear.

## Mutation flow

Booking creation / edit / delete continue to use the existing per-band
endpoints. After a successful mutation, callers should invoke
`ref.read(bookingsWindowProvider.notifier).refresh()` to reload the
full window. We don't try to merge a single mutation into the loaded
list — simplicity over micro-optimization.

(This isn't a change from the current behavior — the existing screen
already fully refetches on mutation.)

## Open items to verify during implementation

- The `subtractMonths` / `subtractDays` helpers don't ship with Dart's
  `DateTime` directly. Use `DateTime(now.year, now.month - N, day)` —
  Dart normalizes negative months. Confirm with a unit test.
- `ItemPositions.itemLeadingEdge` semantics: 0.0 means item top is at
  the viewport top, 1.0 means at the viewport bottom. The anchor
  alignment passes the same value through to `jumpTo(alignment: ...)`.
  Verify on the smoke test that the anchored item lands in the same
  visual position.
- The Laravel `BookingsController::indexForUser` already supports
  `status` and `year` filters. Confirm the new `from`/`to` params
  compose cleanly with them when called concurrently — should be
  additive (`AND`-combined) on the same query builder.
