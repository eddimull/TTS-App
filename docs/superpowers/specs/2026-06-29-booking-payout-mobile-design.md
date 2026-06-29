# Booking Payout (Mobile) — Design Spec

**Date:** 2026-06-29
**Status:** Approved design, pending implementation plan
**Repos:** `tts_bandmate` (Flutter mobile) + `TTS` (Laravel API)

## Context

The TTS web app has a per-booking **Payout** page (`/bands/{band}/booking/{booking}/payout`) that shows how the booking's money is distributed to each band member across all of the booking's performances, and lets the user shape that distribution. The mobile app has **none of this**. Mobile currently surfaces only *client-facing* financials on a booking (price, amount paid, balance due, payment records). A member's personal payout share exists only in a separate aggregate Stats screen, never tied to a specific booking, and there is no per-member breakdown at the booking level at all.

This feature brings **full parity** with the web payout page to mobile: see who gets paid what across performances, and change the payout flow (switch config, edit per-event attendance, add/remove adjustments). Editing attendance is in scope because attendance is what weights each member's share.

The authoritative payout math (`BandPayoutConfig::calculatePayouts`) stays server-side. Mobile never recomputes payouts — it renders server results and re-fetches after every mutation.

## Scope

In scope:
- New **mobile API endpoints** (Laravel) for booking-level payout: view breakdown, add/delete adjustment, switch config, set event-member attendance.
- New **Flutter payout slice** under `features/bookings/`: model, repository, provider, screen.
- Entry point: a "Payout" tile on the booking detail screen (paired with the existing "Payments" tile), shown only when `booking.price > 0`.

Out of scope:
- Creating/editing payout **configs** themselves (flow diagrams). Mobile only *switches among* existing configs. Config authoring stays on web / the existing `payout-flow` mobile endpoints.
- Optimistic UI. Mutations show a brief inline spinner and re-fetch.

## Backend (Laravel `TTS` repo)

New routes in `routes/api.php` under the existing mobile booking group, handled by `App\Http\Controllers\Api\Mobile\BookingsController`. These wrap the **same model methods** the web `BookingsController` already uses (`getOrCreatePayout`, `BandPayoutConfig::calculatePayouts`, `Payout::recalculateAdjustedAmount`), returning JSON instead of Inertia props.

| Method | URI | Action | Notes |
|---|---|---|---|
| GET | `/bands/{band}/bookings/{booking}/payout` | `payout` | Full breakdown payload (below). `read:bookings`. |
| POST | `/bands/{band}/bookings/{booking}/payout/adjustments` | `storePayoutAdjustment` | `write:bookings`. |
| DELETE | `/bands/{band}/bookings/{booking}/payout/adjustments/{adjustment}` | `destroyPayoutAdjustment` | `write:bookings`. |
| PUT | `/bands/{band}/bookings/{booking}/payout/configuration` | `updatePayoutConfiguration` | `write:bookings`. |
| PATCH | `/bands/{band}/bookings/{booking}/events/{event}/members/{member}/attendance` | `updateMemberAttendance` (new) | `{member}` = `event_members.id`. `write:bookings`. |

### Validation rules (mirror web)
- **Adjustment store:** `amount: required|numeric`, `description: required|string|max:255`, `notes: nullable|string`.
- **Config switch:** `payout_config_id: required|exists:band_payout_configs,id` — controller must verify the config's `band_id` matches the route band.
- **Attendance:** `attendance_status: required|in:confirmed,attended,absent,excused`.

### Attendance naming decision
The DB column and `EventMember` model use **`attendance_status`** with values `confirmed/attended/absent/excused`. An older web `EventMembersController` validates a differently-named `status` field with a different value set. The new mobile endpoint standardizes on **`attendance_status` / the four DB values**. Do **not** touch the legacy web endpoint.

### GET payout response shape
```jsonc
{
  "payout": { "id": 999, "base_amount": 10000.00, "adjusted_amount": 9750.00, "payout_config_id": 42 },
  "config": { "id": 42, "name": "Standard Split", "is_active": true } | null,
  "result": {                       // calculatePayouts() output, dollars
    "total_amount": 9750.00,
    "band_cut": 1950.00,
    "distributable_amount": 7800.00,
    "member_payouts": [
      { "type": "member", "name": "Alice Johnson", "user_id": 42, "roster_member_id": 15,
        "role": "Vocalist", "amount": 2600.00, "payout_type": "attendance_weighted",
        "events_attended": 3, "total_events": 3, "weight": 1.0 }
    ],
    "payment_group_payouts": [      // present only when config uses payment groups
      { "group_name": "Players", "group_id": 1, "member_count": 3, "total": 5200.00,
        "payouts": [ { "user_id": 42, "user_name": "Alice Johnson", "role": "Vocalist",
                       "payout_type": "equal_split", "amount": 2600.00 } ] }
    ],
    "total_member_payout": 7800.00,
    "remaining": 0.00
  },
  "adjustments": [ { "id": 7, "amount": -250.00, "description": "Gas / travel", "notes": "Reimbursed to Bob" } ],
  "events": [
    { "id": 100, "label": "Fri Apr 12 · Gala", "value": 3333.00,
      "members": [ { "id": 555, "user_id": 42, "name": "Alice Johnson", "attendance_status": "attended" } ] }
  ],
  "available_configs": [ { "id": 42, "name": "Standard Split", "is_active": true } ]
}
```

Mutation responses: adjustment store returns the created adjustment; delete returns 204; config switch and attendance update return the **refreshed `result`** (or 200 + message and let the client re-fetch — client re-fetches the full GET regardless for simplicity).

### Backend tests
Feature tests per endpoint following existing mobile-API test conventions: auth/band scoping (member of band vs not), validation failures, and the recalculation side-effects (adding an adjustment changes `adjusted_amount`; switching config changes `member_payouts`; changing attendance re-weights amounts).

## Mobile (Flutter `tts_bandmate` repo)

New slice under `lib/features/bookings/`:

### Data (`data/models/booking_payout.dart`)
```
BookingPayout            basePrice, adjustedTotal, bandCut, distributable,
                         config: PayoutConfigRef?, availableConfigs: List<PayoutConfigRef>,
                         members: List<MemberPayout>, groups: List<PayoutGroup>,
                         adjustments: List<PayoutAdjustment>, events: List<PayoutEvent>
MemberPayout             name, role?, amount, eventsAttended?, totalEvents?, weight?, userId?
PayoutGroup              groupName, total, members: List<MemberPayout>
PayoutAdjustment         id, amount, description, notes?
PayoutEvent              id, label, value, members: List<PayoutEventMember>
PayoutEventMember        id, userId?, name, attendanceStatus
PayoutConfigRef          id, name, isActive
```
Hand-written `fromJson` factories with null-coalescing, matching the repo's existing model convention (no codegen). Renders **groups when present, else flat `members`** — same fallback as web.

### Repository (`data/booking_payout_repository.dart`)
Methods over the Dio `api_client`: `fetchPayout`, `addAdjustment`, `deleteAdjustment`, `updateConfiguration`, `updateAttendance`. New path constants in `core/network/api_endpoints.dart`.

### Provider (`providers/booking_payout_provider.dart`)
`BookingPayoutNotifier` — Riverpod `AsyncNotifier`, family-keyed by `bookingId`. Holds the breakdown. Every mutation calls its endpoint, then re-fetches the GET payout (server is authoritative). A per-section "busy" flag drives inline spinners.

### Screen (`screens/booking_payout_screen.dart`)
Cupertino, section order (approved mockup):
1. **Summary header** — base price; adjusted total when adjustments exist; Total / Band cut / Distributable stat tiles.
2. **Config selector** — current config name + "Active" badge; tap → Cupertino action sheet of `availableConfigs`; selection → `updateConfiguration` → refresh.
3. **Member payouts** — headline list: name, **role**, attendance (X/Y), amount; current user's row highlighted. Grouped sections w/ subtotals when payment groups are used.
4. **By performance** (multi-event only) — each event w/ value; per-member **inline attendance pill** (tap → action sheet of the four statuses → `updateAttendance` → refresh, re-weighting payouts).
5. **Adjustments** — list w/ tap/swipe-to-delete + "Add adjustment" sheet (amount, description, optional notes → `addAdjustment`).

States: no active config → warning card (no editable link on mobile); `price <= 0` → no Payout tile / not reachable.

### Entry point
Add a "Payout" tile to `booking_detail_screen.dart` next to "Payments", gated on `booking.price > 0`, routing to the new screen. Register the route in `core/config/router.dart`.

### Mobile tests
- Model `fromJson`: flat-members case, grouped-payment-groups case, adjustments + events parsing.
- Notifier: each mutation triggers a re-fetch (fake repository, `ProviderContainer` pattern).

## Verification

**Backend:** `docker compose exec app php artisan test --filter=Payout` (mobile payout feature tests) in the TTS repo — never run php/artisan on the host.

**Mobile:** `flutter test` for new unit tests; `flutter analyze` clean. Manual end-to-end with `flutter run`: open a multi-event booking with `price > 0` → tap Payout → confirm breakdown matches the web payout page for the same booking → switch config and confirm amounts change → toggle a member's attendance on one event and confirm their share re-weights → add and delete an adjustment and confirm the adjusted total updates.

**Cross-repo:** verify the GET payload field names match the Flutter `fromJson` keys exactly (the contract in this doc is the source of truth).
