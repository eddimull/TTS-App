---
name: Finances Feature — Implementation
description: Route placement, provider shape, and screen conventions for the finances hub (unpaid/paid bookings with currency totals, year/search/status filtering)
type: project
---

The finances feature lives at `lib/features/finances/` with the standard slice layout (data/models, data/repository, providers, screens).

**Route placement:** `/finances` is a ShellRoute child (alongside `/bookings`, `/more`, etc.) so it gets the bottom nav bar. It is accessed via `context.push('/finances')` from the More screen. Tapping a row navigates to the existing booking detail screen via `context.push('/bookings/$bandId/${booking.id}')` — no separate detail screen was added.

**Provider shape (updated):** Both `unpaidServicesProvider` and `paidServicesProvider` are `AutoDisposeAsyncNotifierProviderFamily<_, List<FinanceBooking>, FinancesParams>`. They take a `FinancesParams({required int bandId, required int year})` family arg. The screen constructs `_params` from its local state and watches `unpaidServicesProvider(_params)` / `paidServicesProvider(_params)`. Changing year causes a fresh family instance (and a new API fetch); name/status are filtered client-side only.

**Why changed from non-family:** Added year filtering; the year param needs to flow into the API call, making a family provider the cleanest approach (matches the bookings feature pattern exactly).

**FinancesParams equality:** Both `==` and `hashCode` are implemented based on `bandId` and `year` so Riverpod correctly identifies distinct family instances.

**Repository:** `fetchUnpaid(bandId, {int? year})` and `fetchPaid(bandId, {int? year})` pass `year` as `queryParameters: year != null ? {'year': year.toString()} : null`.

**Sticky controls header (`_StickyControls`):** Four rows inside a blurred backdrop card (matching bookings_screen pattern exactly):
1. `CupertinoSegmentedControl` — Unpaid / Paid tab
2. `CupertinoSearchTextField` — name filter (client-side, no API call)
3. `_StatusPills` — All / Confirmed / Pending / Draft / Cancelled (client-side)
4. `_YearStepper` — triggers new API fetch on change

Header height is 220px to accommodate all four rows. `shouldRebuild` checks tab, nameQuery, statusFilter, and year.

**Filter application:** After receiving `bookings` from the provider the screen applies `nameQuery` and `statusFilter` client-side before passing the resulting `filtered` list to both `_SummaryBanner` and `SliverChildBuilderDelegate` — so the summary total always reflects the filtered slice.

**Summary banner:** Rendered as index 0 in the `SliverChildBuilderDelegate` (offset `index - 1` for actual booking cards). Total is computed inline from the filtered list.

**Status values:** API returns lowercase strings — 'confirmed', 'pending', 'draft', 'cancelled'. The `_kStatusFilters` list uses `null` for "All".

**Currency totals:** `double.tryParse(b.amountDue ?? '0') ?? 0` fold pattern; formatted with `NumberFormat.currency(symbol: '\$')`.

**Amount due color:** `CupertinoColors.systemRed` when tab is unpaid, `CupertinoColors.systemGreen` on paid tab. The left accent bar on each card mirrors this color.

**How to apply:** Use the `FinancesParams` family pattern for any feature needing both bandId and a user-controlled API parameter (year, month, etc.). For purely local filtering (text search, enum pills), apply after the provider's data callback rather than putting it in the provider.
