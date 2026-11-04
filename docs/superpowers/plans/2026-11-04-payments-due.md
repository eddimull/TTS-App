# Payments Due: Plan

Repos: `TTS` (Laravel + Vue, PR to `staging`) and `tts_bandmate` (Flutter, PR to `main`). The backend ships first.
Design: https://claude.ai/artifact/Pf5yaM6RmRwBDXATkBp5XR

Includes the booking-card deposit row already on `feat/booking-finances-deposit` in both repos (uncommitted).

## Decisions from Eddie

- Direction A: a Due tab with one row per payment, grouped Overdue / Next 30 days / Later.
- Home stays calendar-first: a dot on the menu, a count on the Finances row, no card.
- A balance is "Due now" from 7 days before the first event and overdue only after the performance. The contract says
  10 days, but by verbal agreement clients may pay on or before the performance.
- Clients don't use the app and only have the web portal. This is an owner view; the portal does not change.
- A deposit is due 3 weeks after signing.
- Only confirmed, contracted bookings appear.
- Owners only for now. A finance role may come later, so keep the check in one place.
- A bell notification fires when a payment goes overdue.
- The deposit row ships with this work.

## Payment rules (backend, one service: `PaymentDueService`)

A booking qualifies when `status = confirmed`, `price > 0` and `contract.signed_at` is set. `contract_option` is not
used: a web upload can leave it as `none` on a genuinely signed contract, so the signing date is the truth.

For a qualifying booking, payments are applied to the deposit first:

- Deposit owed = `max(0, expected_deposit - paid)`, due `signed_at + 3 weeks`.
- Balance owed = `amount_due - deposit owed`, due `start_date - 7 days`.
- If the deposit's date is on or after the balance's date (signed close to the event), show one row: "Balance",
  the full amount owed, on the balance's date.
- Rows with nothing owed are dropped.

Grouping, compared by date:

- Overdue: a deposit past its due date, or a balance once the first event's date has passed. Only these drive the dot,
  the count and the bell.
- Next 30 days: anything due today through +30. A balance inside its 7-day window reads "Due now" and sorts first.
- Later: beyond that.
- Older: any unpaid payment whose first event was over 90 days ago, deposit or balance. Collapsed by default, and it
  never drives the dot, the count or the bell. These may be payments nobody recorded (22 rows, $69,041 in local data).

## Backend

1. **Signing date.** Migration adding nullable `contracts.signed_at`. Backfill completed contracts from `updated_at`,
   the best information available, so existing dates may be approximate. Set it in
   `ContractCompletionService::markCompleted` and both upload paths (`BookingsController::uploadContract`, mobile
   `uploadContract`). `getContractSignedDateAttribute` reads the column.
2. **False "completed" on send.** `storeContractPdf` always sets `completed`, including when it is called just before
   a PandaDoc send, so a failed send looks signed. Move the status out so only the upload path sets it. Test the
   failure path.
3. **`PaymentDueService`** with unit tests for every rule above.
4. **API.** `GET /api/mobile/bands/{band}/finances/due`, owner-gated, returning rows, group totals and the overdue
   count. Eager-load `contract` and `payments` to avoid N+1.
5. **Bell.** `PaymentOverdue` notification to band owners (database only; `PushDatabaseNotification` also sends it to
   their devices), plus a `NotificationPresenter` case deeplinking to `/bookings/{band}/{id}/payments`. A daily
   `payments:notify-overdue` command, with a `payment_overdue_notices` table (unique on booking + type) so each payment
   notifies once. **It only notifies for payments that went overdue in the last 3 days**, so old debts stay silent on
   release without any first-run state, and a few missed scheduler runs are still caught.
6. **Web.** `GET /finances/due` for the bands the user owns, as a new `Finances/Due.vue`, grouped per band. Add the
   overdue and balance states to `PaymentSummary.vue`.

## App

1. `FinanceDue` model, repository method and provider, with caching and invalidation like the other finance data.
2. Due tab, first and default for owners; everyone else keeps today's four tabs and default.
3. Red dot on the dashboard menu icon and "N overdue" on the Operations Finances row, owners only.
4. `DepositFinanceRow` gains overdue styling, wording for unsigned contracts, and is hidden when there's no contract.
   Add the balance due line. "Balance due" turns red only when overdue, on both finance cards.
5. A row tap pushes the booking's Payments screen; recording a payment refreshes the Due data.

## Tests and verification

- Backend: rules, signing date on all three paths, failed send, owner gating, notify-once, first-run silence.
- Web: Vitest in CI mode (`npm run test:pipeline`) for `Due.vue` and `PaymentSummary.vue`.
- App: model parsing, Due tab groups and empty states, dot and count visibility by role.
- On the phone against local data, and the web page in a browser, before calling it ready.

## Not in this work

- A finance role.
- The reminder commands' possible repeat sends (their +/-1 day window has no dedupe).
