# Library Aggregation & Filtering — Design

**Status:** Approved (brainstorming complete)
**Date:** 2026-05-02
**Branch (target):** new feature branch off `main`

## Problem

The library screen (charts / sheet music) is currently scoped to one band at a time. The user must change the active band via the dashboard's band selector to see another band's charts. As users join more bands, this friction grows.

The dashboard already solves an analogous problem for events: it aggregates across all of the user's bands into a single calendar and lets the user filter band-by-band via a floating filter sheet. The library should follow the same pattern.

A second, smaller problem: the library `+` button always creates a chart in the currently-selected band. With aggregation, "currently selected" is no longer meaningful for this screen, so creation needs an explicit band-picker step — analogous to `CreateBookingSheet`.

## Goals

1. Library screen displays charts from every band the user belongs to in a single alphabetized list.
2. A filter sheet (modeled on `CalendarFilterSheet`) lets the user hide bands; the list and alphabet scrubber update live.
3. Each row shows the band's avatar (replacing the per-chart initials avatar), making the band of origin instantly readable.
4. The `+` button opens a band-picker sheet (modeled on `CreateBookingSheet`) listing real bands and a "Personal" row. Solo users (no real bands yet, or exactly one real band and no personal band yet) skip the sheet and go straight to the create form for that band; everyone else sees the picker.
5. After creating a chart, the user lands on the chart detail screen so they can immediately upload PDFs.

## Non-goals

- No persistence of filter state across app restarts (resets, like dashboard).
- No pagination on the aggregated endpoint (charts lists are small per-band; dashboard precedent doesn't paginate).
- No partial-success / per-band error shape — endpoint either returns everything or fails.
- No filter axes beyond bands (search field continues to handle title/composer; public/uploads/etc. are not added).
- No changes to `CreateChartScreen` itself, the chart detail screen, or upload flow.
- No automatic garbage collection of stale `hiddenBandIds` after band membership changes.

## Architecture

Three layers, each mirroring an existing precedent in the codebase:

### Backend (Laravel)

A new aggregated endpoint, mirroring `/api/mobile/dashboard`:

- **Route:** `GET /api/mobile/charts` (added to the unauthenticated-band group in `routes/api.php` — does not need the per-band `mobile.band:read:charts` middleware since it scopes by membership server-side).
- **Controller:** new method on `App\Http\Controllers\Api\Mobile\MusicController` (e.g., `chartsForUser`), alongside the existing per-band `charts` method.
- **Auth:** standard mobile sanctum guard.
- **Response:** flat array of charts, each shaped via the existing mobile chart resource plus a nested `band` object: `{id, name, avatar_url, is_personal}`. Enough for the client to render avatar, group, and filter without extra round trips.
- **Scope:** every band the authenticated user belongs to (use the same membership lookup the dashboard uses for events, or adapt the existing non-mobile `ChartsController::getChartsForUser` query).
- **No pagination.**

Existing per-band routes (`/api/mobile/bands/{bandId}/charts/...`) stay untouched. Creation, deletion, and uploads continue to use them.

### Flutter data layer

- **`Chart` model** gains a nullable nested `ChartBand` (`{id, name, avatarUrl, isPersonal}`). Nullable so charts loaded via the per-band endpoint (e.g., chart detail re-fetches) still parse.
- **`LibraryRepository`** gains `getAllCharts()` calling the new endpoint. `getCharts(bandId)` stays for places that explicitly want one band.
- **`LibraryNotifier.build()`** switches from "wait for `selectedBandProvider`, load that band" to "load all bands' charts." The library screen no longer reads `selectedBandProvider`.
- **`createChart(bandId, ...)`** continues to call the per-band endpoint and optimistically inserts into state. The new chart's `band` is stamped from the band picked in the sheet (the client knows the band metadata since it just rendered the picker).
- **`deleteChart(bandId, chartId)`** unchanged — operates by chart id; band id only used to address the per-band endpoint.

### Flutter UI

#### `LibraryFilterState` + `libraryFilterProvider`

Same shape as `CalendarFilterState` minus the event-types axis:
- `Set<int> hiddenBandIds`
- `bool get isActive => hiddenBandIds.isNotEmpty;`
- `int get activeCount => hiddenBandIds.length;`
- Methods: `toggleBand(int id)`, `clear()`.
- Value-equality via `SetEquality<int>`.
- In-memory only; resets on app restart.

#### `LibraryFilterSheet`

Visually identical to `CalendarFilterSheet`, with the "EVENT TYPES" section removed:
- Drag handle → "Filter" header with right-aligned "Clear All" button (only when `isActive`) → "BANDS" section label → horizontal scrollable row of band cells (64×80, blue-bordered when visible, opacity 0.4 when hidden, `HapticFeedback.selectionClick()` on tap).
- Bands list comes from `auth.bands` (same source as the calendar filter), so a band with zero charts still has a toggle.
- Personal band rendered with `BandAvatar.forUser(...)` and the label "Personal" (matches calendar filter sheet).

#### `LibraryFilterButton`

Floating filter button modeled on `CalendarFilterButton`:
- Filled when `isActive`, with a small badge showing `activeCount`.
- Position: top-right of the body, just below the nav bar, with right-padding equal to the alphabet scrubber width (16px) so it doesn't overlap the scrubber.

#### `CreateChartSheet`

Modeled on `CreateBookingSheet`:
- Drag handle → section label "Add chart to" → one row per non-personal band using `BandIdentityChip` → hairline → "Personal" row (person icon, "Personal library", subtitle "Just for me, not tied to a band"; spinner replaces chevron while `personalBandProvider.ensureExists()` runs).
- Personal-creation failure shows an error message in red below the sheet rows; sheet stays open.

#### `LibraryScreen` rewrite

- Outer shell drops the `selectedBandProvider`-based band-resolution wrapper.
- `_LibraryBody` watches `libraryProvider` directly and `libraryFilterProvider` for filter state.
- Before grouping into alphabet sections, the chart list is filtered: `charts.where((c) => c.band == null || !filter.hiddenBandIds.contains(c.band!.id))`. The `band == null` clause is defensive — should not occur in practice on the aggregated endpoint.
- `_ChartRow` swaps the colored-initials circle for `BandAvatar.forBand(...)` (or `BandAvatar.forUser(...)` for personal). The initials helpers (`_avatarColor`, `_avatarInitials`) become unused and are removed.
- Floating `LibraryFilterButton` overlaid in the top-right, inside the same `Stack` that already overlays the alphabet scrubber and letter overlay.
- `+` button (in `_BottomSearchBar`) routes through a new `_handleAddTapped(BuildContext)` method:
  - 0 real bands (only personal, or none yet): ensure personal band exists, push `CreateChartScreen(bandId: personal.id)`.
  - 1 real band, no personal-creation needed: skip sheet, push form for that band.
  - Otherwise: open `CreateChartSheet`. On selection, dismiss sheet, push form for picked band.
- After `CreateChartScreen.pop(chart)`, the screen calls `context.push('/library/${chart.id}', extra: chart.bandId)` (chart detail), so the user immediately sees the chart and can upload to it.

## Data flow

### On screen open
1. `LibraryScreen` mounts and watches `libraryProvider`.
2. `libraryProvider.build()` calls `repo.getAllCharts()` → returns `List<Chart>` with non-null `band` on each.
3. Screen reads `libraryFilterProvider`; applies the hidden-band filter before `_buildGroups`.
4. Alphabet grouping drops empty letters automatically.
5. Filter button shows badge when filter is active.

### On filter toggle
1. Tap a band cell in the sheet → `notifier.toggleBand(id)`.
2. State changes; screen rebuilds; groups re-derive. No network roundtrip.

### On `+` create
1. Tap `+` → screen calls `_handleAddTapped(context)`.
2. Picker shown, except solo users (no real bands or exactly one real band and no personal band yet) — for them, skip the sheet and push the create form for the resolved band directly.
3. Selected band id flows into `CreateChartScreen(bandId: pickedId)`.
4. `CreateChartScreen` calls `LibraryNotifier.createChart(bandId, ...)`; the resulting `Chart` is optimistically inserted into the merged list (the new chart's `band` field is set from the sheet selection so it can be filtered/avatared correctly).
5. `CreateChartScreen.pop(chart)` returns. Library screen routes to chart detail.

### On delete
- `LibraryNotifier.deleteChart(bandId, chartId)` removes from local state by chart id. No structural change.

## File layout

### New / changed backend files
```
TTS/app/Http/Controllers/Api/Mobile/MusicController.php          (add method: chartsForUser)
TTS/routes/api.php                                                (add route: GET /api/mobile/charts)
TTS/tests/Feature/Api/Mobile/MobileChartsAggregateTest.php       (new)
```
Mobile charts already live in `Api\Mobile\MusicController` (see existing `charts`, `chartDetail`, `storeChart`, etc.). Adding the aggregated method there keeps all mobile charts logic in one controller. The existing non-mobile `ChartsController::getChartsForUser` can be referenced as a starting point for the cross-band scoping query, but the response shape must match the mobile chart resource (with the added nested `band` block).

### New / changed Flutter files
```
lib/features/library/data/models/chart.dart              (extend: add ChartBand, optional band field)
lib/features/library/data/library_repository.dart        (add: getAllCharts)
lib/features/library/providers/library_provider.dart     (rewrite build() and refresh path)
lib/features/library/providers/library_filter_provider.dart    (new — mirrors calendar_filter_provider)
lib/features/library/widgets/library_filter_button.dart        (new — mirrors calendar_filter_button)
lib/features/library/widgets/library_filter_sheet.dart         (new — bands section only)
lib/features/library/widgets/create_chart_sheet.dart           (new — mirrors create_booking_sheet)
lib/features/library/screens/library_screen.dart         (rewrite per the UI section above)
lib/core/network/api_endpoints.dart                      (add: mobileChartsAll)
```

## Error handling & edge cases

- **Aggregated load fails** → `libraryProvider` enters `AsyncError`; existing `ErrorView` with retry handles it.
- **User in zero bands** → empty array; existing `EmptyStateView` shown; `+` ensures personal and routes to form.
- **No charts anywhere** → existing `EmptyStateView`. Filter sheet still functional.
- **Filter hides every band → empty list** → distinct empty state: "All bands hidden" with a "Show all" link calling `notifier.clear()`. (Mirrors dashboard.)
- **Personal-band creation fails inside `CreateChartSheet`** → red error text under sheet rows; spinner clears; sheet stays open. Mirrors `CreateBookingSheet`.
- **Chart created for a hidden band** → not auto-unhidden; chart is in state but filtered out until user un-hides. Consistent with their explicit filter choice.
- **Stale `hiddenBandIds` for a band the user left** → harmless; filters by id, no match. Resets on app restart anyway.
- **Search + filter compose** → both apply; search runs over the filter-narrowed list. Existing search rendering (flat un-grouped list) unchanged.
- **Alphabet scrubber with filter active** → `_buildGroups` already drops empty letters; no extra code needed.

## Testing

### Backend (Laravel)
File: `TTS/tests/Feature/Api/Mobile/MobileChartsAggregateTest.php`

- `test_returns_charts_from_all_user_bands` — user in 2 bands with 3 charts each; endpoint returns 6.
- `test_excludes_charts_from_bands_user_is_not_in` — third band exists with charts; not in response.
- `test_each_chart_includes_band_block` — `band.id`, `band.name`, `band.avatar_url`, `band.is_personal` all present.
- `test_includes_personal_band_charts` — user has personal band with charts; included with `is_personal: true`.
- `test_unauthenticated_user_returns_401`.
- `test_returns_empty_array_when_user_has_no_bands`.

### Flutter unit tests

`test/features/library/providers/library_filter_provider_test.dart`
- Toggle band adds/removes from `hiddenBandIds`; `isActive` flips correctly.
- `clear()` empties the hidden set.
- Value-equality via `SetEquality<int>`.

`test/features/library/data/models/chart_test.dart`
- `Chart.fromJson` parses nested `band` object including `is_personal`.
- Tolerates missing `band` field (degrades to null) for per-band-endpoint responses.

`test/features/library/providers/library_provider_test.dart`
- `build()` calls `getAllCharts()` on the (mocked) repo.
- `createChart` inserts optimistically; resulting chart has the picked band stamped.
- `deleteChart` removes by chart id regardless of band.

### Flutter widget tests

`test/features/library/widgets/library_filter_sheet_test.dart`
- Renders one cell per band in `auth.bands`.
- Tapping a cell calls `notifier.toggleBand(id)` and dims the cell.
- Personal band renders with `BandAvatar.forUser(...)` and "Personal" label.
- "Clear All" only visible when `isActive`.

`test/features/library/widgets/library_filter_button_test.dart`
- Active state toggles fill; badge shows hidden-count.

`test/features/library/widgets/create_chart_sheet_test.dart`
- Multi-band: real bands + Personal row.
- Tapping a band invokes `onBandSelected(bandId)`.
- Tapping Personal calls `ensureExists()` then `onBandSelected(personal.id)`; spinner shown during.
- Personal-creation failure shows error; sheet stays open.

`test/features/library/screens/library_screen_test.dart`
- Renders charts from multiple bands sorted alphabetically with band avatars.
- Filter hide → list updates; alphabet scrubber's letter for hidden-only sections disappears.
- "All bands hidden" empty state appears with a "Show all" action that calls `clear()`.
- Single-band user: `+` skips `CreateChartSheet`.
- Multi-band user: `+` shows `CreateChartSheet`.

### Manual verification (per project CLAUDE.md UI rule)
- Run on Linux desktop with a multi-band test account.
- Confirm library list shows charts from all bands with correct avatars.
- Confirm filter toggles update list and scrubber in real time.
- Confirm `+` flow lands on chart detail screen ready for upload.
- Confirm personal-only user sees the no-sheet shortcut.

## Decisions captured (for future reference)

- **Aggregate-by-default** (Q1=a): library mirrors dashboard's "show everything, filter down" model.
- **Band avatar replaces initials** (Q2=a): row identity becomes the band, matching the calendar marker visual language.
- **Bands-only filter** (Q3=a): no public/uploads/price toggles; search continues to handle text axes.
- **Picker for multi-band, shortcut for solo** (Q4=mix of a/b): single-band → straight to form; multi-band → picker with real bands + Personal row.
- **Backend aggregation endpoint** (Q5=b): new `/api/mobile/charts` instead of client-side fan-out, matching dashboard.
- **Filter independent of creation** (Q6=a): picker always shows the full set of bands regardless of filter state.
- **Push to detail after create** (Q7=c): immediate upload affordance without filter ambiguity.
