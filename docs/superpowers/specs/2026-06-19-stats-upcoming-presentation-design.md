# Stats: present upcoming earnings across charts and cards

**Date:** 2026-06-19
**Repos:** `TTS-App` (Flutter mobile) and `TTS` (Laravel web `/stats` page)
**Builds on:** the earned-vs-upcoming split (`upcoming_earnings`, per-row `is_upcoming`, per-year `upcoming_total`) already shipped.

## Goal

Gigs that are on the calendar but not yet played should still show what the user is
expected to make. Surface that "upcoming" money in the three stats visualizations:

1. **Earnings by Year** — stacked bar: earned (green) with upcoming stacked on top (gray).
2. **Earnings by Band** — donut: each band gets a separate upcoming slice in a lighter
   shade of the band's own color, labeled "Band name (upcoming)".
3. **Bookings by Year** — compact inline card line: total bookings, earned so far,
   upcoming. The standalone per-year/band total figure is removed.

## Decisions (from brainstorming)

- Earnings by Year: **stacked** (one bar/year), not grouped. Upcoming = gray on top.
- Earnings by Band: upcoming slice is a **lighter shade of that band's own color**
  (not a neutral gray), so each band stays visually paired.
- Bookings by Year: **compact inline** format — `43 bookings · $1,000 earned · $400 upcoming`.
  Upcoming portion shown only when > 0. Remove the standalone total from the card header.
- A gig dated today or later (and undated bookings) = upcoming; date strictly in the
  past = earned. (Unchanged from existing split.)

## Architecture — no backend changes

All three views derive from the existing `bookings_by_year` payload, which already
contains **one row per booking — earned and upcoming, every band, every year (including
future-only years)** — each tagged with `band_id`, `band_name`, `is_upcoming`,
`user_share`, plus per-year `year_total` / `upcoming_total` / `booking_count` /
`upcoming_booking_count`.

Two client-side aggregations (a Vue `computed` on web, a Dart getter/helper on mobile),
each computed once from `bookings_by_year`:

- **byYearWithUpcoming**: per year → `{ year, earned, upcoming }`, summing each row's
  `user_share` split by `is_upcoming`. Future-only years appear naturally (earned = 0).
- **byBandWithUpcoming**: flatten all rows → group by `band_id` →
  `{ bandId, bandName, earned, upcoming }`. Upcoming-only bands appear (earned = 0).

The existing earned-only `by_year` and `by_band` payload fields are left in place for
back-compat; these two charts switch to the derived data.

## View details

### 1. Earnings by Year (stacked bar)

- One bar per year; full height = total expected that year.
- Two stacked series: **Earned** (green) on bottom, **Upcoming** (gray) on top.
- Future-only years render as all-gray bars.
- Legend: "Earned" / "Upcoming". Tooltips show each segment's dollar value.
- **Web** (`resources/js/Pages/UserStats/Index.vue`): Chart.js bar with two datasets,
  `scales: { x: { stacked: true }, y: { stacked: true } }`. Data from `byYearWithUpcoming`.
- **Mobile** (`lib/features/stats/screens/widgets/earnings_bar_chart.dart`): add a second
  gray stacked segment above the existing green earned segment per bar.

### 2. Earnings by Band (donut)

- Up to two slices per band: earned (band color) and upcoming (same hue, ~40% alpha),
  the latter labeled `"<Band> (upcoming)"`. Zero-value slices are skipped.
- Upcoming-only bands show just the light slice.
- **Web** (`Index.vue`): Chart.js doughnut; build `labels`, `data`, `backgroundColor`
  arrays by emitting up to two entries per band from `byBandWithUpcoming`. Upcoming color
  is the band's assigned color converted to ~0.4 alpha.
- **Mobile** (`lib/features/stats/screens/widgets/earnings_pie_chart.dart`): same pairing
  logic; upcoming segment uses `bandColor.withValues(alpha: 0.4)`.

### 3. Bookings by Year (compact inline card)

- Year header subtitle becomes a single line:
  `<n> bookings · $<earned> earned · $<upcoming> upcoming`
  (the "· $X upcoming" segment is omitted when upcoming is 0).
- **Remove** the standalone earned-total figure currently shown in the year header
  (web: the right-aligned `year_total`; mobile: the `• $yearTotal` in the subtitle).
- Expandable per-booking detail rows are unchanged (they keep their "Upcoming" badges
  and "TBD" placeholders for undated rows).
- **Web** (`Index.vue`): rework the year-header markup in the bookings breakdown section.
- **Mobile** (`bookings_by_year_section.dart`): rework the `_YearGroup` header subtitle.

## Testing

- **Mobile** (`test/features/stats/`): unit-test the two new aggregation helpers —
  byYearWithUpcoming (incl. a future-only year) and byBandWithUpcoming (incl. an
  upcoming-only band) — from a `bookings_by_year` fixture. Widget-level: confirm the
  card line renders count/earned/upcoming and omits the upcoming segment when zero.
- **Web** (`TTS`): the charts are Chart.js canvas render; cover the aggregation logic if
  it's extracted to a testable function. No PHP changes, so no new backend tests.
- Re-run existing stats suites (mobile `test/features/stats`, backend
  `UserStatsServiceTest` / `MobileStatsTest`) to confirm no regressions.

## Out of scope

- No changes to `UserStatsService` or the API payload.
- No change to the earned/upcoming classification rule.
- Travel/mileage and locations sections unchanged.
