# Finances: Revenue & reporting on mobile

**Date:** 2026-06-26
**Repos:** `TTS-App` (Flutter mobile) and `TTS` (Laravel backend — new mobile endpoint)
**Builds on:** the existing mobile Finances screen (Unpaid/Paid tabs, year filter) and the
web `Finances/Revenue` page.

## Goal

Bring the web **Revenue Overview** to the mobile app so a band leader can, on the go,
see how the band is doing financially. This is the first slice of a broader
"financial-tools parity" effort; later slices (deposits, invoices, payout adjustments)
get their own spec → plan → implementation cycle.

The mobile Revenue view mirrors the web page for the **currently selected band**:

1. **Summary cards** — Total Revenue, Current-Year Revenue, Years Active.
2. **Revenue-by-year bar chart** — one bar per year (most-recent → oldest or chronological).
3. **Revenue-by-year table** — year, revenue, and year-over-year % change, plus a total row.

## Decisions (from brainstorming)

- **Placement:** a third segment in the existing Finances segmented control —
  **Unpaid · Paid · Revenue** (Approach A). Keeps all money tooling in one screen, no
  new nav, reuses the screen's band-scoping and refresh patterns.
- **Scope:** full parity for v1 — summary cards + table with YoY change + bar chart.
- **Chart:** use `fl_chart` (already a dependency; already used in
  `lib/features/stats/screens/widgets/earnings_bar_chart.dart`). Mirror that widget's
  style — no new dependency.
- **Audience:** band leader / owner. Revenue lives inside Finances, which is already a
  leader-oriented area; no new role gating is introduced beyond what the Finances tab
  already enforces.
- **Single-band:** unlike web (which loops over all of a user's bands), mobile is always
  in a single-band context (`selectedBandProvider`). The endpoint and view are scoped to
  one band.

## Architecture

### Backend — new mobile endpoint (`TTS`)

Add `GET /api/mobile/bands/{band}/finances/revenue`, handled by a new `revenue()` method
on `app/Http/Controllers/Api/Mobile/FinancesController.php`, registered in `routes/api.php`
alongside the existing `mobile.finances.*` routes (with the same auth/band-scoping
middleware the siblings use).

The aggregation mirrors the web's `FinanceServices::getBandRevenueByYear`, but scoped to
the one `{band}` rather than a collection:

```
SELECT YEAR(date) AS year, SUM(amount) AS total
FROM payments
WHERE band_id = {band} AND date IS NOT NULL   -- pending invoices have no date; excluded
GROUP BY YEAR(date)
ORDER BY year DESC
```

Response shape (amounts in **cents**, matching the web payload where the Vue divides
`total / 100`):

```json
{
  "revenue": [
    { "year": 2026, "total": 1250000 },
    { "year": 2025, "total": 980000 }
  ]
}
```

Reuse `getBandRevenueByYear`'s query logic where practical (e.g. extract a single-band
helper on `FinanceServices` that the existing multi-band method can also call), to keep
one source of truth for "what counts as revenue."

**Authorization:** same as the sibling `unpaid`/`paid` mobile endpoints — the requesting
user must have finance-viewing access to the band. Follow whatever policy/gate those
endpoints already apply; do not invent a new rule.

### Mobile (`TTS-App`)

New files under `lib/features/finances/`:

- `data/models/band_revenue.dart` — `BandRevenue` model: a list of `RevenueYear { int year, int totalCents }`,
  parsed from the `revenue` array. Provide derived getters:
  - `totalCents` — sum of all years.
  - `currentYearCents` — total for `DateTime.now().year`, or null if absent.
  - `yearsActive` — count of year rows.
  - amounts are converted cents → dollars for display via the existing currency
    formatter pattern (`NumberFormat.currency`).
- `data/finances_repository.dart` — add `fetchRevenue(int bandId)` calling the new endpoint
  (sibling to `fetchUnpaid`/`fetchPaid`).
- `providers/finances_provider.dart` — add a `revenueProvider` (family on bandId), an
  `AsyncNotifier` mirroring the existing `unpaidServicesProvider` / `paidServicesProvider`
  with a `refresh()`.
- `screens/widgets/revenue_view.dart` — the Revenue tab body: summary cards, chart, table.
- `screens/widgets/revenue_bar_chart.dart` — `fl_chart` bar chart modeled on
  `earnings_bar_chart.dart` (single-series bars, year labels on the x-axis, currency on
  the y-axis, tap tooltip showing `year` + formatted revenue).

Changes to existing files:

- `screens/finances_screen.dart` — extend the `_FinancesTab` enum with `revenue`, add the
  third segment to the `CupertinoSegmentedControl`, and render `RevenueView` when that tab
  is active. The Unpaid/Paid-specific chrome (year stepper, name search, status pills)
  applies only to those two tabs; the Revenue tab shows its own body and shares only the
  pull-to-refresh and nav bar.
- `core/network/api_endpoints.dart` — add `mobileBandFinancesRevenue(int bandId)`.

### Data flow

```
RevenueView (watches revenueProvider(bandId))
  → revenueProvider → FinancesRepository.fetchRevenue(bandId)
    → GET /api/mobile/bands/{bandId}/finances/revenue
  → BandRevenue model
    → summary cards (derived getters)
    → RevenueBarChart (per-year bars)
    → revenue table (per-year rows + YoY% + total)
```

### Year-over-year change

Computed client-side in the table, matching the web logic: for a year at list index `i`
(list ordered newest→oldest), compare against the next (older) year `i+1`:
`change% = (current − previous) / previous × 100`. The oldest row shows `N/A`. Up = green
with an up-arrow, down = red with a down-arrow, zero = neutral dash. Mirror the web
`getYearOverYearChange` / `formatPercentage` behavior.

## Error / empty / loading states

Follow the existing Finances screen conventions:

- **Loading:** `CupertinoActivityIndicator` (sliver-filled), as the Unpaid/Paid tabs do.
- **Error:** `ErrorView` with `ErrorView.friendlyMessage(e)` and a retry that calls
  `revenueProvider(bandId).notifier.refresh()`.
- **Empty** (no payments with a date — a brand-new band): `EmptyStateView` with a
  money/chart icon, title like "No revenue yet", subtitle "Recorded payments will appear
  here." No cards, table, or chart are shown when there are zero year rows.
- **Pull-to-refresh:** the existing `CupertinoSliverRefreshControl` refreshes the active
  tab; extend it to refresh `revenueProvider` when the Revenue tab is selected.

## Testing

Mobile (unit tests, mirroring `test/` structure; `ProviderContainer` + fake repo):

- `BandRevenue.fromJson` parses the `revenue` array; derived getters
  (`totalCents`, `currentYearCents`, `yearsActive`) compute correctly, including the
  empty-list case and a list with no current-year row.
- Year-over-year helper: positive, negative, zero, single-year (N/A), and divide-by-zero
  (previous year total 0) cases.
- `revenueProvider` loads via a fake repository and exposes the model; `refresh()` re-fetches.

Backend (`TTS`, Feature test under `tests/Feature/Api/Mobile/`):

- `GET /finances/revenue` returns years grouped/summed correctly for the band, excludes
  payments with a null date, and is scoped to the requested band only (payments from other
  bands do not leak in).
- Authorization: a user without finance access to the band is rejected, matching the
  sibling endpoints.

No widget/golden tests (consistent with the repo's current test surface).

## Out of scope (future slices)

Deposits, invoices/receipts, payout adjustments, payment groups, the all-payments listing,
and Stripe/client-portal features. Each is its own spec later. This slice is read-only
revenue reporting for the selected band.
