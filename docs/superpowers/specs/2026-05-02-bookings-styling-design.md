# Bookings screen — styling consistency pass

## Goal

Bring the Bookings screen into visual consistency with the rest of the app
(Library is the established pattern). Add the missing search, filter, and add
controls; replace the broken year stepper + auto-scroll with a working "jump
to nearest upcoming" behavior driven by a horizontal month strip.

## Out of scope

- Booking-detail / booking-form screens.
- Pagination of the bookings list. The provider switches to fetching all of
  the user's bookings in one call. If perf becomes a problem we revisit.
- Backend changes. The existing `GET` endpoint must already accept a
  no-`year` call (verify during implementation; if it doesn't, we either
  loosen the server param or send a sentinel from the client — no new
  filtering or pagination is added on this pass).
- Widget integration / golden tests. Project baseline has no widget tests;
  unit tests only on this pass.

## Existing patterns being mirrored

- `lib/features/library/screens/library_screen.dart` — bottom search bar
  with circular `+`, floating filter button overlay, filter sheet shell,
  empty/error states.
- `lib/features/library/widgets/library_filter_button.dart` — circular
  floating button, badge count, shadow.
- `lib/features/library/widgets/library_filter_sheet.dart` — modal popup
  shell with drag handle, "Filter" title, "Clear All" action, section
  labels, horizontal band-avatar row.
- `lib/features/library/providers/library_filter_provider.dart` — Riverpod
  filter notifier shape.

## Layout & chrome

Replace the current top-right `+`, 116pt frosted pinned sliver, status
filter pills, and year stepper with:

- `CupertinoSliverNavigationBar` with `largeTitle: 'Bookings'`. No trailing
  action.
- Pinned `SliverPersistentHeader` directly under the nav bar — horizontal
  month-chip strip (~52pt tall). Hidden when the booking list is empty.
- `SliverList` of booking cards + `_MonthHeader` rows (unchanged from
  today).
- Bottom bar (mirrors Library's `_BottomSearchBar`): `CupertinoSearchTextField`
  on the left, circular `+` add button on the right.
- Floating circular filter button (mirrors `LibraryFilterButton`) overlaid
  on the list, anchored below the nav bar — see "Floating filter button
  positioning" below.

The `_FilterPills`, `_YearStepper`, `_StickyControls`, and the nav-bar
trailing add button are removed.

## Floating filter button positioning

Library's `LibraryFilterButton` is currently positioned at `top: 8` from the
screen top, which puts it under the system status bar (battery icon). Fix
on this pass for both screens by anchoring the button below the nav bar's
collapsed extent.

Implementation: place the button as a `Positioned` child of the screen's
outer `Stack`, with `top: MediaQuery.of(context).padding.top + 50`. (44pt
collapsed nav bar + ~6pt clearance.) The large title scrolls away above
the collapsed bar, so this clearance is correct in both expanded and
collapsed nav bar states.

This fix is applied to both Bookings (new) and Library (existing) in the
same PR.

## Filter sheet

Single bottom-sheet modal opened by the floating filter button. Same
shell as `LibraryFilterSheet`:

- `showCupertinoModalPopup` with rounded-top container, drag handle,
  centered "Filter" title, "Clear All" button on the right when any
  filter is active.
- **STATUS** section: row of pill chips (All / Confirmed / Pending /
  Draft), **single-select** (mirrors today's `_BookingsFilter`).
  Tapping a chip sets the active status; tapping the currently selected
  chip is a no-op. Visual style matches the existing `_FilterPills`
  widget being removed.
- **BANDS** section: horizontal avatar row identical to
  `LibraryFilterSheet._BandsRow`, multi-select via tap to hide/show.
  Reuses the existing `BandAvatar` widget.

Bookings filtered out of the list disappear. If all bookings are
filtered out, show an `EmptyStateView` with a "Show all" button that
calls `notifier.clear()` (mirrors Library's "all bands hidden" empty
state).

## Month strip & "jump to nearest upcoming"

Pinned `SliverPersistentHeader` directly under the nav bar, ~52pt tall,
horizontal scrolling row of month chips.

**Chip data:** Built from the (filtered) booking list. Walk all visible
bookings, collect unique `(year, month)` pairs that have at least one
booking, sort ascending. One chip per pair, label `MMM yy` (e.g.
`JAN 26`). If there are no visible bookings, the strip is hidden.

**Chip styling:** Same pill styling as today's `_FilterPills`. Selected
chip = filled `systemBlue` background + white text, others =
`tertiarySystemBackground` + label color. Each chip carries a
`GlobalKey` so the strip can `Scrollable.ensureVisible` to it.

**`_selectedMonthKey`** (String, e.g. `"2026-03"`) lives in screen
state.

### Initial "jump to nearest upcoming" on load

1. Find the index of the first booking whose `parsedDate` is ≥
   `DateTime.now()`. If none exists, fall back to the last booking
   (most recent past).
2. Set `_selectedMonthKey` to that target booking's `(year, month)`.
3. After the next frame, scroll the **vertical** list to the
   `_HeaderItem` for that month using a `GlobalKey` per header and
   `Scrollable.ensureVisible(key.currentContext!, alignment: 0.0)`.
4. Scroll the **horizontal** strip to center the selected chip
   using `Scrollable.ensureVisible` on the chip's key with
   `alignment: 0.5`.

Track `_lastJumpedFingerprint` (the booking list's identity hash or a
stable hash over its IDs) so refreshes don't re-jump after the user has
scrolled.

### Tapping a chip

Set `_selectedMonthKey` to the tapped chip; `Scrollable.ensureVisible`
on that month's `_HeaderItem` key. No data refetch.

### Vertical scroll → strip selection

`ScrollController` listener on the vertical list. On scroll, find the
topmost visible `_HeaderItem` (via key positions / `RenderBox` global
positions) and update `_selectedMonthKey` if it changed. Frame-aligned
via `addPostFrameCallback` to avoid jank. The strip auto-scrolls to
keep the selected chip visible (`ensureVisible` with `alignment: 0.5`).

### Year handling

Year is implicit in the chip labels (`JAN 26` vs `JAN 27`). No
standalone year stepper. The `userBookingsProvider` no longer takes a
`year` param.

## State changes

### New providers

- **`bookingsFilterProvider`** (Riverpod `Notifier`) —
  shape `{ status: BookingStatus, hiddenBandIds: Set<int> }`.
  Methods: `setStatus(BookingStatus)`, `toggleBand(int)`, `clear()`.
  Computed: `isActive` (any constraint applied),
  `activeCount` (status ≠ "All" counts as 1, plus one per hidden band
  — drives the badge).

  `BookingStatus` is a new enum mirroring the current `_BookingsFilter`:
  `all`, `confirmed`, `pending`, `draft`. Defaults to `all`. The filter
  is single-select (a booking can only have one status at a time).

### Modified providers

- **`userBookingsProvider`** — drop the `year` param. Becomes
  parameterless `FutureProvider<List<BookingSummary>>`. The repository
  call drops `year` accordingly.

### Screen state (`_BookingsScreenState` / `_BookingsBodyState`)

Added:

- `TextEditingController _searchController` + `String _query`.
- `String? _selectedMonthKey`.
- `String? _lastJumpedFingerprint`.
- `Map<String, GlobalKey> _headerKeys` (one per visible month, keyed
  by month key like `"2026-03"`).
- `Map<String, GlobalKey> _chipKeys` (one per chip).
- `ScrollController` listener on the existing `_scrollController` to
  drive `_selectedMonthKey` from scroll position.

Removed:

- `_BookingsFilter _filter` — moved into `bookingsFilterProvider`.
- `int _selectedYear`.
- `int? _lastScrolledYear` / `_BookingsFilter? _lastScrolledFilter`.
- `_StickyControls`, `_FilterPills`, `_YearStepper` widgets.

## Search

Live filter on the bookings list as the user types. Pure helper
function:

```dart
bool bookingMatchesQuery(BookingSummary booking, String query)
```

Case-insensitive `contains` against the trimmed lowercase query. Returns
true for empty / whitespace-only queries. Match scope:

- `booking.name`
- `booking.venueName`
- For each `BookingContact` in `booking.contacts`:
  - `contact.name`
  - `contact.email`
  - `contact.phone`

Filter is applied to the visible list AFTER the band/status filter is
applied. The month strip and "jump to nearest" do NOT respond to the
search query — they continue to reflect the band/status-filtered
window. (Search is meant to find a specific booking; once found, the
user taps the card.)

## Card style and list

Booking card, month divider headers, and empty/error/loading states are
unchanged. They already match app conventions. The colored left border
+ `StatusChip` on each card remain the at-a-glance status signal now
that the status pill row is gone.

## Add flow

Existing `_onNewBooking` / `CreateBookingSheet` flow is preserved as-is.
The trigger moves from the nav-bar trailing button to the bottom bar
`+` button (matching Library's `_BottomSearchBar.onAdd`). No behavioral
change to the sheet itself.

## Testing

Following the project's existing pattern (unit tests with
`ProviderContainer` + fakes; no widget integration tests):

- **`bookingsFilterProvider` unit tests** — set status, toggle band,
  clear, `isActive` / `activeCount` math (including: status = "All" +
  0 hidden bands → 0; status = "Confirmed" + 0 hidden bands → 1;
  status = "All" + 2 hidden bands → 2; status = "Pending" + 1 hidden
  band → 2).
- **`bookingMatchesQuery` unit tests** — name match, venue match,
  contact name/email/phone match, case-insensitive, empty query,
  whitespace-only query, no match.
- **"Nearest upcoming" selection unit test** — pure helper
  `findNearestUpcomingIndex(List<BookingSummary>, DateTime now) → int?`
  covering: today inside the range, today before the range, today
  after the range, single-element list, empty list, all-past list,
  all-future list.
- **Month-strip building unit test** — pure helper that produces
  sorted unique `(year, month)` keys from a booking list, including
  dedup and chronological order.

Widget tests for scroll-sync behavior are deferred (matches project
baseline of no widget tests yet).

## Open items to verify during implementation

- Backend `GET /api/mobile/me/bookings` (or whichever endpoint backs
  `userBookingsProvider`) accepts a no-`year` call. If not, either
  loosen the server param or have the client send a sentinel that
  returns all years.
- Library's existing filter button position fix
  (`top: MediaQuery.padding.top + 50` instead of the current
  `_kFilterButtonTopInset = 8.0`) doesn't regress any other
  Library-screen interaction.
