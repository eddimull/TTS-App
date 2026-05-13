# Configurable Booking Deposit

**Date:** 2026-05-13
**Repos:** `tts_bandmate` (Flutter mobile), `TTS` (Laravel backend + Vue/Inertia web)

## Problem

The booking deposit is hardcoded to 50% of `booking.price` in three independent places: the Laravel `Bookings` model accessor (`getExpectedDepositAmountAttribute`), the contract PDF Blade template, the web WYSIWYG contract editor, and the Flutter mobile contract preview. Bands cannot configure the deposit per booking. The deposit feeds the generated contract text and the automated payment-reminder emails, so it must be consistent across all four surfaces.

## Goals

- A band can set the deposit on a booking as either a percent of the total price or an exact dollar amount.
- The setting flows into the generated contract (PDF and editable previews on both web and mobile) and into the automated deposit-reminder emails.
- Once a contract is signed, the deposit is locked.
- Existing bookings continue to behave exactly as they do today (50% deposit) without user action.

## Non-goals

- Optional / "no deposit" bookings. Every booking has a deposit.
- Editing the deposit independently per event in a multi-event booking. The deposit lives on the booking, not the event.
- Snapshotting the resolved dollar value at contract-signing time. The signed PDF is already the binding artifact; we lock the inputs instead.
- Moving deposit onto the `contracts` table. The deposit is a booking attribute that also appears in the contract terms; it is not exclusively a contract concept.

## Approach

Add two columns to the `bookings` table — `deposit_type` (`percent` | `amount`) and `deposit_value` (decimal). Rewrite the existing `expected_deposit_amount` accessor on the `Bookings` model to compute from these instead of from a hardcoded 0.50. Every other deposit-related accessor (`is_deposit_paid`, `deposit_due`, `deposit_due_date`, `needs_deposit_reminder`) already routes through `expected_deposit_amount`, so the reminder pipeline picks up the change with no further work. Lock state is derived from `contract.status === 'completed'`; we do not store a lock flag.

The Flutter mobile form, the Vue web form, the PDF Blade, the web WYSIWYG editor, and the Flutter contract preview all read the new fields (and the computed `expected_deposit_amount`) from the API.

## Data Model

### Migration

New columns on `bookings`:

| Column | Type | Default | Null |
|---|---|---|---|
| `deposit_type` | `string` (enum-like: `percent`, `amount`) | `'percent'` | no |
| `deposit_value` | `decimal(10, 2)` | `50.00` | no |

`deposit_value` holds either a percent (0–100, up to 2 decimals) or a dollar amount (0+, up to 2 decimals). The column type is the same in either case; the meaning is given by `deposit_type`.

The migration also backfills existing rows to `('percent', 50.00)` — preserving the current behavior for every existing booking.

### Model — `App\Models\Bookings`

- Add `deposit_type`, `deposit_value` to `$fillable`.
- Cast `deposit_value` to `decimal:2`.
- Rewrite `getExpectedDepositAmountAttribute()`:
  - If `deposit_type === 'percent'`: return `number_format($price * ($deposit_value / 100), 2, '.', '')`.
  - If `deposit_type === 'amount'`: return `number_format($deposit_value, 2, '.', '')`.
  - When `price` is null or 0, return `'0.00'`.
- Existing accessors (`is_deposit_paid`, `deposit_due`, `deposit_due_date`, `needs_deposit_reminder`) are unchanged.

### API resource

Append three fields to the booking JSON resource (used by both mobile REST and web Inertia props):

- `deposit_type` (string)
- `deposit_value` (string — decimal serialized to match `price`)
- `expected_deposit_amount` (string — resolved dollar amount)

## Validation (Laravel FormRequest)

On booking update:

- `deposit_type`: required, `in:percent,amount`.
- `deposit_value`: required, numeric, `>= 0`.
- If `deposit_type === 'percent'`: `deposit_value <= 100`.
- If `deposit_type === 'amount'`: `deposit_value <= price` (using the validated input's price, which may itself have just changed in the same request).
- If `$booking->contract_signed_date !== null`, reject any change to `deposit_type` or `deposit_value` with a 422: `"Deposit is locked because the contract is signed."`

The lock check happens in a custom rule (or a method on the FormRequest) so the error key surfaces under both `deposit_type` and `deposit_value`.

## UI — Mobile (`booking_form_screen.dart`)

A new row appears below the existing Price field in the same `CupertinoFormSection`:

```
┌─────────────────────────────────────────────┐
│ Price       $ 1,000.00                      │
├─────────────────────────────────────────────┤
│ Deposit     [ 50      ]    [ $ │ % ]        │
│             = $500.00                       │
└─────────────────────────────────────────────┘
```

- `CupertinoTextFormFieldRow`, `keyboardType: numberWithOptions(decimal: true)`, prefix `Deposit`.
- Trailing `CupertinoSlidingSegmentedControl<DepositType>` with `$` and `%`.
- Secondary-color caption beneath the field showing the computed counterpart: `= $500.00` in `%` mode, `= 50%` in `$` mode. Suppressed when undefined.
- Per-state behavior:
  - **Price empty/0 + mode `%`:** field disabled with helper text "Enter a price above to use percent."
  - **Price empty/0 + mode `$`:** field active, counterpart hidden.
  - **Signed contract:** field and segmented control disabled, caption "Locked — contract is signed."
- **Mode-switch:** clears the input value; no silent conversion. The caption gives the user the converted number if they want it.
- **Validation messages (inline below field):**
  - Percent > 100: "Percent must be between 0 and 100."
  - Amount > price: "Deposit cannot exceed the booking price."
- **Accessibility:**
  - `Semantics(label: 'Deposit type: dollar amount or percent')` wraps the segmented control.
  - The text field's `Semantics.label` is "Deposit, in dollars" or "Deposit, as percent" depending on mode.

## UI — Web (`resources/js/Pages/Bookings/Components/BookingForm.vue`)

A new field group appears directly below the Price input, mirroring the mobile layout:

- Numeric input with two Tailwind-styled toggle `<button>` elements (`$` and `%`) on the right, using `aria-pressed` for state.
- Computed counterpart line beneath in muted text.
- Same per-state behavior and validation as mobile.
- Same mode-switch behavior (clear on toggle).
- Reuses whichever currency-input composable/utility powers `form.price` so behavior is consistent across the two fields.
- Locked state reads from `booking.contract?.status === 'completed'`.

## Contract surfaces

Both web and mobile render contract previews. Today each surface hardcodes `price / 2` for the deposit sentence AND for the "remaining balance" sentence — both must change.

### Mobile — `contract_fixed_header.dart`

- Replace `_halfPrice` with a `Deposit.resolved(booking)` helper returning `{ depositAmount, remainingAmount }`.
- `depositAmount`: prefer `booking.expectedDepositAmount` from the API; if absent, compute client-side from `depositType` and `depositValue`.
- `remainingAmount`: `price − depositAmount`.
- Apply to both the deposit sentence and the remaining-balance sentence.

### Web — `resources/js/Pages/Bookings/Components/EditableContractWYSIWYG.vue`

- Same replacement. Introduce a `useDeposit(booking)` composable (or a local `computed`) returning `{ depositAmount, remainingAmount }` with the same preference rule (backend value first, client computation as fallback).
- Apply to both lines 107 and 120.

### PDF — `resources/views/pdf/bookingContract.blade.php`

- Replace both `${{ number_format($booking->price/2, 2) }}` occurrences with `${{ $booking->expected_deposit_amount }}` and `${{ number_format($booking->price - $booking->expected_deposit_amount, 2, '.', '') }}` respectively.

### Contract text rule

The customer-facing contract always shows resolved dollar amounts, never percents. Whether the band entered `50%` or `$500`, the PDF reads "Buyer will pay a deposit of $500.00…" — the final binding number.

## Mobile data model changes

- `BookingDetail` (`lib/features/bookings/data/models/booking_detail.dart`): add `depositType` (String), `depositValue` (String), `expectedDepositAmount` (String?) from JSON.
- `EventDraft` / `event_draft.dart` (the PATCH payload): add `depositType` and `depositValue`, included only when changed (existing diff pattern).
- Booking repository methods that PATCH stay shape-compatible.

## Reminders

No code changes. `SendDepositReminders` reads `needs_deposit_reminder`, which uses `deposit_due_date` (3 weeks after `contract_signed_date`) and `is_deposit_paid` (compares `amount_paid` to `expected_deposit_amount`). The `DepositPaymentReminder` notification renders `$booking->deposit_due`, which falls through to `expected_deposit_amount`. Rewriting that accessor automatically propagates the new value everywhere reminders touch.

## Edge cases

| Case | Behavior |
|---|---|
| `deposit_type === 'percent'` and `price` is null/0 | `expected_deposit_amount` returns `"0.00"`. Reminders see `is_deposit_paid === true` (any paid amount ≥ 0), so no reminder fires. PDF prints `$0.00`. Acceptable; an unset price is itself an unfinished booking. |
| `deposit_type === 'amount'` with amount > current price (price later edited down) | No auto-clamp. If unsigned, next form save fails validation. If signed, the lock prevents the edit entirely. |
| Stale mobile cache hits 422 on a now-signed contract | The error surfaces as a `CupertinoAlertDialog`; the form re-fetches the booking and the row becomes read-only. |
| Mode toggle with a populated field | The field clears. We never silently rewrite a user's number. |

## Tests

### Backend (`tests/`)

- `BookingsControllerTest`:
  - PATCH with valid percent succeeds.
  - PATCH with percent > 100 fails 422.
  - PATCH with valid amount ≤ price succeeds.
  - PATCH with amount > price fails 422.
  - PATCH on a signed-contract booking fails 422 with the "locked" message.
  - The booking show/index response includes `deposit_type`, `deposit_value`, `expected_deposit_amount`.
- `Unit/Models/BookingsTest` (new or expanded):
  - `expected_deposit_amount` returns correct values for both modes.
  - Backfilled legacy bookings (`percent`, `50.00`) match the pre-change number.
- `PaymentReminderNotificationsTest`: `DepositPaymentReminder` renders the resolved amount for both modes.
- `Feature/BookingContractPdfTest` (new or extended): PDF rendering uses `expected_deposit_amount` and `price − expected_deposit_amount` for the two sentences.

### Web (Vitest, `resources/js/tests/`)

- `useDeposit` composable: returns correct `{ depositAmount, remainingAmount }` for both modes, including 0/null price guard.
- `BookingForm.vue`: mode toggle clears the value; locked state when contract is signed; client-side validation messages appear for out-of-range inputs.
- `EditableContractWYSIWYG.vue`: both deposit and remaining-balance lines reflect both modes.

### Mobile (`test/`)

- `BookingDetail.fromJson` parses the new fields.
- `EventDraft` diff includes `depositType`/`depositValue` only when changed.
- Widget test for `booking_form_screen.dart` mode toggle: clear-on-toggle, percent-disabled when price is 0, locked state when contract is signed.

## Rollout

1. Backend migration (adds columns + backfills).
2. Backend model + FormRequest + API resource changes.
3. PDF Blade update.
4. Web BookingForm + WYSIWYG + composable.
5. Mobile model + form + contract header.
6. Verify on both clients that signed bookings show locked deposit and that reminders pick up the resolved value.

Backend ships first because both clients depend on the new API fields. The backend change is backwards-compatible — the backfill ensures every existing booking computes the same number it did before, so old clients that don't yet know about the fields keep working.
