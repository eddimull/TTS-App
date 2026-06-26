# Finances: Trends chart + time travel on mobile

**Date:** 2026-06-26
**Repos:** `TTS-App` (Flutter mobile) and `TTS` (Laravel backend — new mobile endpoint)
**Builds on:** the mobile Finances screen (Unpaid · Paid · Revenue tabs) and the web
`Finances/PaidUnpaid` page (`AllPaidUnpaid.vue`), which is a configurable per-month
paid/unpaid chart with "time travel."

## Goal

Bring the web Paid/Unpaid **chart** — the most-used finance tool — to mobile as a new
**Trends** tab. It shows, for a selected year, money paid vs. outstanding vs. forecast vs.
the band's cut, **per month**, plus how many bookings drove each month. It also supports
**time travel**: viewing the financial picture as it stood on a past date, optionally
overlaid against the current picture with deltas.

The flat Unpaid/Paid list tabs stay as-is (they're used for drilling into individual
bookings); this is an additional, analytical view.

## Decisions (from brainstorming)

- **Placement:** a 4th segment in the Finances control — **Unpaid · Paid · Revenue · Trends**.
- **Chart series (single $ axis):** four dollar series per month —
  - **Paid** (bar) — sum of `amount_paid`.
  - **Unpaid / outstanding** (bar) — sum of `max(0, price − amount_paid)`.
  - **Forecast** (line) — sum of `price` (full contracted value, paid or not).
  - **Band cut / net** (line) — sum of `net_amount` (band's take after the active payout config).
- **Booking count:** NOT a second chart axis. Shown two ways (decision "B1 + tap tooltip"):
  - an always-visible **per-month count row** directly beneath the chart, column-aligned to
    the month bars, so a low month visibly correlates with few bookings;
  - a **tap tooltip** on a month showing that month's exact figures (count + the four $ values).
- **Year selector:** choose which year to view; options come from the years present in the data.
- **Time travel (decision "T1"):** an inline **"As of <date>" pill** (tap → date picker) and a
  **"vs Current" toggle**. No drag slider (tap-to-pick is faster on mobile).
  - Snapshot = the picture using only bookings created on/before the chosen date.
  - With "vs Current" on, the chart overlays the snapshot series (solid) against the current
    series (faded), and the summary cards show **delta badges** (current − snapshot).
- **Data source (decision "server buckets"):** a new mobile endpoint returns compact
  per-month series; bucketing and snapshot filtering happen server-side. Dart just renders.

## Architecture

### Backend — new mobile endpoint (`TTS`)

Add `GET /api/mobile/bands/{band}/finances/trends`, handled by a new `trends()` method on
`app/Http/Controllers/Api/Mobile/FinancesController.php`, registered in `routes/api.php` in
the existing `mobile.band:read:bookings` group (same auth as the sibling finance routes).

Query params:
- `year` (int, required-ish; default current year) — the calendar year to bucket.
- `snapshot_date` (nullable date `Y-m-d`) — when present, the primary series is computed as
  of that date.
- `compare_with_current` (bool, default false) — when true **and** `snapshot_date` is set,
  also return the current (unfiltered) series.

Computation (reuses existing, already-snapshot-aware backend methods):

1. Resolve `$band` from `mobile_band` (middleware), wrap as a single-band collection.
2. **Primary series:** `FinanceServices::getPaidUnpaid([$band], $snapshotDate)` →
   gives `$band->paidBookings` and `$band->unpaidBookings`, each booking carrying
   `price`, `amount_paid`, `net_amount`, `start_date`, `status`.
3. **Bucket by month** for the requested `year` (server-side port of the web
   `processDataByMonth`): for each non-cancelled booking whose `start_date` falls in `year`,
   accumulate into its month (`1..12`):
   - `paid   += amount_paid`
   - `unpaid += max(0, price − amount_paid)`
   - `forecast += price`
   - `net    += net_amount`
   - `count  += 1`
   Amounts are summed in **dollars** then emitted as **cents** (`round($v * 100)`) to match
   the cents contract used elsewhere in the mobile API.
4. **Compare series:** if `compare_with_current` and `snapshot_date`, repeat steps 2–3 with
   `$snapshotDate = null` to get the current (unfiltered) series.

Response shape (12 month rows always present, months with no data are zero-filled; cents):

```json
{
  "year": 2026,
  "snapshot_date": "2025-06-15",
  "available_years": [2026, 2025, 2024],
  "months": [
    { "month": 1, "paid": 0, "unpaid": 0, "forecast": 0, "net": 0, "count": 0 },
    { "month": 2, "paid": 300000, "unpaid": 120000, "forecast": 420000, "net": 84000, "count": 2 }
    /* … through month 12 */
  ],
  "current_months": [ /* same shape, present only when compare_with_current && snapshot_date */ ]
}
```

`available_years`: the distinct years present across the band's paid+unpaid bookings
(unfiltered), descending — drives the mobile year selector.

`totals` are NOT sent; the client derives year totals (and deltas) by summing `months` /
`current_months`, keeping the payload minimal and the summation logic in one place.

**Authorization:** identical to the sibling `paid`/`unpaid`/`revenue` endpoints
(`mobile.band:read:bookings`); no new rule.

### Mobile (`TTS-App`)

New files under `lib/features/finances/`:

- `data/models/finance_trends.dart`:
  - `TrendMonth { int month; int paidCents; int unpaidCents; int forecastCents; int netCents; int count; }`
  - `FinanceTrends { int year; String? snapshotDate; List<int> availableYears; List<TrendMonth> months; List<TrendMonth>? currentMonths; }`
    with `fromJson`, and derived **totals** getters over `months` (and `currentMonths`):
    `totalPaidCents`, `totalUnpaidCents`, `totalForecastCents`, `totalNetCents`, `totalCount`,
    plus matching `current*` getters and `delta*` getters (`current − snapshot`) used by the
    compare badges. Cents → dollars only at display.
- `data/finances_repository.dart` — add
  `fetchTrends(int bandId, {required int year, String? snapshotDate, bool compareWithCurrent = false})`.
- `providers/finances_provider.dart` — add a `TrendsParams { bandId, year, snapshotDate, compareWithCurrent }`
  (value-equality) and a `trendsProvider` family `AsyncNotifier` with `refresh()`, mirroring
  the existing finance providers.
- `screens/widgets/trends_view.dart` — the Trends tab body (sliver): controls row
  (year selector + "As of" pill + "vs Current" toggle), the chart, the per-month count row,
  the summary cards (with delta badges when comparing), and loading/error/empty states.
- `screens/widgets/trends_chart.dart` — the `fl_chart` chart: grouped paid/unpaid bars +
  forecast/net line series on a single $ axis, month labels on the x-axis, a tap tooltip
  (`BarTouchData`) showing the tapped month's count + four $ figures. When comparing, the
  current series render faded/secondary. Models on the stats `EarningsBarChart` style.
- `screens/widgets/trends_count_row.dart` — the always-visible per-month booking-count row,
  column-aligned under the chart (same 12-slot layout as the x-axis).

Changes to existing files:

- `screens/finances_screen.dart` — add `trends` to `_FinancesTab`, add the 4th segment
  (tighten segment padding so four fit), render `TrendsView` for that tab, and include it in
  the pull-to-refresh switch. The Unpaid/Paid-only chrome (year stepper, name search, status
  pills) and the bookings provider remain gated to the Unpaid/Paid tabs (Revenue and Trends
  each own their bodies and providers).
- `core/network/api_endpoints.dart` — add `mobileBandFinancesTrends(int bandId)`.

### Data flow

```
TrendsView (year, snapshotDate, compare state held in the view)
  → trendsProvider(TrendsParams) → FinancesRepository.fetchTrends(...)
    → GET /finances/trends?year=&snapshot_date=&compare_with_current=
  → FinanceTrends
    → TrendsChart (bars + lines, tap tooltip)
    → TrendsCountRow (per-month counts)
    → summary cards (+ delta badges when comparing)
```

The year selector, "As of" date, and "vs Current" toggle are local view state; changing any
of them rebuilds `TrendsParams`, which re-watches `trendsProvider` and refetches.

## Interaction details

- **Year selector:** a Cupertino picker / menu seeded from `availableYears`; defaults to the
  current year if present, else the newest available. If the data has no years (no bookings),
  the selector is hidden and the empty state shows.
- **"As of" pill:** shows "All time" when no snapshot; tapping opens a `CupertinoDatePicker`
  (date mode). Picking a date sets `snapshotDate`; a clear ("×") action resets to null and
  also forces "vs Current" off.
- **"vs Current" toggle:** disabled/hidden unless a `snapshotDate` is set. When on, the chart
  overlays current (faded) behind snapshot (solid) and each summary card shows a delta badge
  (green ▲ / red ▼ / neutral) of `current − snapshot`.
- **Tap tooltip:** tapping a month’s bar group shows that month: count + paid + unpaid +
  forecast + band cut, formatted as currency.

## Error / empty / loading states

Follow the Finances/Revenue conventions:

- **Loading:** `CupertinoActivityIndicator` (sliver-filled).
- **Error:** `ErrorView` + `ErrorView.friendlyMessage(e)`, retry calls `trendsProvider(...).notifier.refresh()`.
- **Empty:** if every month in `months` is zero across all series (no bookings for the year),
  show `EmptyStateView` (chart icon, "No activity in <year>", subtitle suggesting another year
  or clearing the snapshot). The controls row (year selector, As-of pill) stays visible so the
  user can change year/date; the chart/count/cards are replaced by the empty state.
- **Pull-to-refresh:** refreshes `trendsProvider` for the current params when the Trends tab is active.

## Testing

Mobile (unit; `ProviderContainer` + fake repo, mirroring existing finance tests):

- `FinanceTrends.fromJson` parses `months`, optional `current_months`, `available_years`,
  `snapshot_date`. Zero-filled months parse. `current_months` absent → `currentMonths` null.
- Derived getters: per-series totals sum `months`; `current*` totals sum `currentMonths`;
  `delta*` = current − snapshot; total-count sums counts; empty/all-zero detection.
- `TrendsParams` value-equality (same fields equal; differing snapshot/compare not equal) so
  the provider family caches/refetches correctly.
- `trendsProvider` loads via fake repo and forwards year/snapshot/compare; `refresh()` re-fetches.

Backend (`TTS`, Feature test `tests/Feature/Api/Mobile/FinanceTrendsTest.php`):

- Buckets paid/unpaid/forecast/net/count by month of `start_date` for the requested year,
  in cents; excludes cancelled bookings; zero-fills empty months; returns 12 month rows.
- `available_years` lists distinct booking years (descending), independent of the `year` filter.
- `snapshot_date` limits the primary series to bookings created on/before that date
  (a later-created booking is excluded from `months` but, with `compare_with_current=1`,
  present in `current_months`).
- `compare_with_current` omits `current_months` unless a `snapshot_date` is also provided.
- Scoped to the band; another band's bookings don't leak. Access control matches siblings (403 for non-members).

No widget/golden tests (consistent with the repo).

## Out of scope

- The web's drag-through-time slider (replaced by tap-to-pick date).
- Multi-band aggregation (mobile is single-band).
- Editing bookings/payments from this view (read-only analytics; the flat tabs handle drilling in).
- Export / CSV download.
