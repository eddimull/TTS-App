# Song-side sheet music linking — design

**Date:** 2026-07-13
**Status:** Approved (approach A + create-flow prefill)

## Problem

Sheet music (charts) can only be associated with a song from the chart side
(`_LinkedSongEditor` on the chart detail screen). The song detail screen shows
its linked charts read-only. Users want to manage the association from the
song side too.

## Constraints & existing capabilities

- A chart has a single `song_id` FK: one song per chart, many charts per song.
- `PATCH /api/mobile/bands/{band}/charts/{chart}` with `song_id` links
  (int) or unlinks (null). Already wrapped by
  `LibraryRepository.updateChartSong()`.
- The charts index eager-loads `song:id,title,artist`, so each chart's
  current link is available to a picker.
- `LibraryRepository.createChart()` already accepts `songId`.
- **No backend changes required.** Pure Flutter change.

## Design (approach A)

All changes hang off the existing **Sheet music** section of
`song_detail_screen.dart`.

### 1. Add sheet music (link existing chart)

- An **Add sheet music** action in the section header (or below the rows).
- Opens a modal popup sheet (`_ChartPickerSheet`) listing the band's charts
  from the existing band-charts provider:
  - Row: chart title; subtitle shows "Linked to <song title>" when the chart
    is already linked to a *different* song; charts already linked to *this*
    song are shown disabled/checked.
  - Top row: **New sheet music…** (see §3).
- Picking an unlinked chart → `updateChartSong(bandId, chartId, songId: song.id)`.
- Picking a chart linked to another song → confirmation dialog
  ("Move from *Song X* to this song?") before the same PATCH. Cancel aborts.

### 2. Unlink from the song side

- Each linked-chart row on the song detail gets an unlink affordance
  (ellipsis/long-press action sheet with "Unlink sheet music"), calling
  `updateChartSong(bandId, chartId, songId: null)`.
- Row tap continues to navigate to the chart detail unchanged.

### 3. Create new chart pre-linked and prefilled

- **New sheet music…** in the picker routes to the existing
  `/library/new` (`CreateChartScreen`) with:
  - `_linkedSong` preset to this song,
  - **title prefilled from the song title**,
  - **composer prefilled from the song artist**.
- `CreateChartScreen` gains an optional `initialSong` parameter; the
  `/library/new` route extra becomes a small `CreateChartArgs` class carrying
  the `BandSummary` plus optional `Song` (with a backward-compatible cast for
  a bare `BandSummary`). Existing callers are unaffected.
- The `BandSummary` needed by the route is resolved from the selected-band /
  bands providers on the song detail screen.

### 4. Refresh & state

- After any link/unlink/create: invalidate the songs provider and the library
  chart providers (same pattern as commit `ba77110` "refresh songs state after
  chart link changes") so `song.charts` and chart screens rebuild.
- A busy guard prevents double-submitting while a PATCH is in flight.

### 5. Error handling

- Failures surface as a `CupertinoAlertDialog` with
  `ErrorView.friendlyMessage(e)`, exactly matching the chart-side
  `_LinkedSongEditor._showError` pattern.

## Testing

Widget tests mirroring `chart_detail_screen_test.dart` conventions:

- Picker lists charts, shows "Linked to X" subtitles, disables charts already
  linked to this song.
- Linking an unlinked chart issues the PATCH and refreshes the section.
- Relink shows the confirmation; cancel does not PATCH; confirm does.
- Unlink action issues PATCH with null and removes the row.
- "New sheet music…" navigates to the create route with song extra; create
  screen prefilling covered by a screen test (title/composer/link preset).
- Failure path shows the friendly error and clears the busy state.

## Out of scope

- Backend/API changes.
- Multi-song-per-chart data model changes.
- Search/filter inside the picker (band chart libraries are small; revisit if
  that changes).
