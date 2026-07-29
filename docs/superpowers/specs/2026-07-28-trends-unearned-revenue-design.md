# Trends: Unearned Revenue Card — Design

**Date:** 2026-07-28
**Status:** Approved
**Repos:** TTS (Laravel backend, PR base `staging`) + tts_bandmate (Flutter app, PR base `main`)

## Problem

The Trends tab's "Paid" figure mixes revenue from executed performances with
deposits collected for performances that haven't happened yet. There is no way
to see how much money should still be sitting in the bank as unearned deposits.
Deposits held for bookings in future years don't appear in the year-scoped view
at all.

## Decision summary

Add a single **Unearned** stat card to the Trends summary cards, backed by one
new top-level field in the existing trends API payload. Point-in-time, all
years, unaffected by the year/snapshot controls.

Considered and rejected: client-side computation from the year-filtered finance
endpoints (duplicates business logic, needs multiple calls) and a dedicated
`/finances/unearned` endpoint (a whole endpoint for one integer the trends call
carries for free).

## Definition (business rule, backend-owned)

`unearned` = sum of `amount_paid` over the band's non-cancelled bookings whose
`start_date` is **strictly after today**, across **all** years, in cents.

- A booking with an event date of today counts as executed (earned), not unearned.
- Fully-paid future bookings count in full (a wedding paid in full six months
  out is 100% unearned).
- Cancelled bookings are excluded.
- Computed fresh on every request; never affected by `year`, `snapshot_date`,
  or `compare_with_current` request params.

## Backend (TTS)

- `FinancesController::trends()` adds a top-level `"unearned"` (int cents) to
  the JSON payload.
- Implemented as a private `unearnedCents($band)` helper mirroring the shape of
  the existing `availableYears()` helper; both use `getPaidUnpaid([$band], null)`
  (no snapshot), so no new queries are introduced.
- Tests in `tests/Feature/Api/Mobile/FinanceTrendsTest.php`:
  - future booking with partial payment contributes its `amount_paid`;
  - fully-paid future booking contributes its full amount;
  - past bookings excluded;
  - cancelled future bookings excluded;
  - booking in a future *year* included;
  - value identical with and without `snapshot_date`.
  - All test dates computed relative to `now()` (no hardcoded time-bomb dates).

## Flutter model + repository (tts_bandmate)

- `FinanceTrends` gains `final int unearnedCents`, parsed from
  `json['unearned']` using the existing null-coalescing style
  (`(json['unearned'] as num?)?.toInt() ?? 0`) so older backend responses
  default to 0 instead of crashing.
- No repository, provider, or endpoint changes — the field rides the existing
  trends fetch.

## Flutter UI

- In `_SummaryCards` (`lib/features/finances/screens/widgets/trends_view.dart`),
  the last row currently holds a lone full-width Forecast card. Unearned joins
  it as a second card in that row.
- Card spec: label `Unearned`, tint `CupertinoColors.systemTeal` (distinct from
  the five tints in use), value via existing `_fmtCents`, **no delta badge**
  (the number is snapshot-independent), plus a small caption
  "as of today, all years" indicating its scope. The caption is an optional
  `caption` parameter added to `_StatCard`, not a new widget.
- Must render cleanly at 320pt width (narrow iPhone).

## Error handling

Nothing new. A missing `unearned` field defaults to 0; a band with no future
deposits legitimately shows $0.00 (the card always renders, never hides).

## Testing & verification

- Backend: feature tests above, run via `docker compose exec app` (never host
  php).
- Flutter: extend `test/features/finances/finance_trends_test.dart` (parsing +
  missing-field default) and add a card-render assertion alongside the existing
  summary-card tests; `flutter analyze` + `flutter test`.
- On-device verification against the local backend (run-on-device skill) before
  the PRs are called done; wait for Copilot review on both PRs.
