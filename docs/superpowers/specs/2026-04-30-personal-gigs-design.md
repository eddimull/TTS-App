# Personal Gigs — Design

**Date:** 2026-04-30
**Status:** Approved, ready for implementation plan

## Problem

A musician using TTS Bandmate often plays gigs that don't belong to any band on the platform — substituting at a church on Sundays, picking up a wedding-band gig, filling in for someone else's group. Today the mobile app has no place to track those gigs. Everything is scoped to a band, every band exists on the platform, and a user wanting to see "what am I playing this weekend" cannot include those off-platform gigs in the view.

We want a single mobile experience where a user sees **all** the gigs they're playing — their real bands' gigs (which already aggregate on the Dashboard) plus their personal/side gigs that aren't tied to any band.

## Use case (anchor scenario)

Eddie plays in two bands on the platform. He also subs for First Baptist Church most Sundays. He should be able to:

1. Open the app and see Sunday's church gig listed on the Dashboard alongside Saturday's gig with one of his real bands.
2. Open the Bookings tab and see all three gigs in the same list.
3. Tap "+" anywhere he creates gigs and choose "Personal gig" to add the church gig.
4. Distinguish at a glance which gigs are with bands and which are personal.

## Backing model: the personal band

Personal gigs are stored as bookings on a `bands.is_personal = true` band, one per user, owned only by that user. This wrapper exists for code reuse — every booking feature (form, detail, contacts, payments, contracts, attached charts, history) works unmodified for personal gigs because they're just bookings.

The user **does not** see this wrapper. They never think "I'm switching to my personal band." They think "I'm adding a side gig." UI treats the personal band as a special destination, not as a peer in band lists.

The backend already supports this:
- `bands.is_personal` boolean column exists
- `BandSummary`/`Bands` models expose `is_personal`
- `POST /api/mobile/bands/solo` is implemented and idempotent — creates the personal band lazily, returns the user's full bands list
- The path-selection onboarding screen already offers "Go Solo" which calls `goSolo`

## Scope

**In scope:**

- "+ Personal gig" creation flow as a peer to "Create booking for [Band]"
- Lazy creation of the personal band the first time the user adds a personal gig (via `POST /bands/solo`)
- Visual identity on aggregated cards: personal gigs show the user's avatar + "Personal" label; band gigs show the band's avatar + name
- Convert the Bookings tab from `selectedBand`-scoped to a true multi-band view (matching the web's behavior)
- A new aggregating endpoint `GET /api/mobile/me/bookings` to back the converted Bookings tab
- Hide the personal band from band-selector screens, band-switcher UIs, and "create booking for [Band]" lists (it has its own entry point)
- Solo-musician path (user has only a personal band) works end-to-end

**Out of scope (separate, future specs):**

- Removing the global `selectedBandProvider` gate from the router. `selectedBandProvider` keeps working as a soft default for Library/Finances/etc.
- Converting Library, Finances, band-settings, or other tabs to multi-band views
- A Calendar surface (if/when added)
- Personal-band visibility / filtering controls beyond what's described above
- A way for a user who went solo to later create or join a real band from inside the app (assumed to be handled by the existing onboarding/Settings flows)

## Architecture

### Backend (one new endpoint)

`GET /api/mobile/me/bookings`
- Authenticated user, no `X-Band-ID` required (the header is irrelevant for this route)
- Returns a paginated list of bookings across **all** bands the user belongs to (real and personal)
- Each item includes the existing booking fields plus a nested `band` object: `{ id, name, logo_url, is_personal }`
- Mirrors the web's Bookings index logic (status filtering, ordering, pagination)
- Pagination matches the convention used elsewhere in the mobile API (cursor or page-based — to be determined by parity with the existing per-band `/bookings` endpoint)

**Verify:** The Dashboard endpoints (upcoming events, upcoming bookings, live-now, upcoming charts) already include enough band info per item for the mobile cards to render `BandIdentityChip`. If any card-feeding payload omits band identity, that payload gains a `band` object too. Each Dashboard card type is verified individually during implementation.

**Verify:** The authenticated user's avatar URL is available on the auth-state user model. If not, the auth/me payload gains an `avatar_url` field. Personal-gig identity chips fall back to generated initials if the user has no avatar.

### Mobile

#### Models

- `BandSummary` (existing) — verify it carries `isPersonal`. Add the field if missing.
- Booking models (`features/bookings/data/models/`) — gain a nested `band` (or flat `bandId`/`bandName`/`bandLogoUrl`/`isPersonalBand` fields, whichever matches existing convention). Mirror the API shape.
- Dashboard card models (`features/dashboard/data/models/`) — same: each card model carries enough band info to render the identity chip.

#### Providers

- **`personalBandProvider`** (new) — lives in `lib/shared/providers/personal_band_provider.dart`. It's small (one derived getter and one mutation), reads from auth state, and is consumed by both the create-booking sheet and any future personal-gig-related glue. A dedicated `features/personal_gigs/` folder isn't warranted at this size.
  - `BandSummary? get personalBand` — derived from `authProvider`'s bands list, filtered by `isPersonal == true`. Returns the first match.
  - `Future<BandSummary> ensureExists()` — if `personalBand` is non-null, returns it. Otherwise calls `POST /api/mobile/bands/solo`, refreshes `authProvider` so the bands list updates, and returns the new band. Idempotent on the backend; safe to retry.

- **Bookings tab provider** (`features/bookings/providers/bookings_provider.dart`) — refactored to fetch from `/api/mobile/me/bookings` instead of the per-band endpoint. The dependency on `selectedBandProvider` is removed for the list screen. Per-band methods used by booking-form / booking-detail / etc. remain.

- **`selectedBandProvider`** (existing) — unchanged. Still used by Library, Finances, band-settings, and any band-scoped Dashboard sections that haven't been converted.

#### Repositories

- `BookingsRepository` gains a `fetchAllForUser({cursor, ...})` method backed by `/me/bookings`. The existing per-band methods stay.

#### Widgets (new)

- **`BandIdentityChip`** (`lib/shared/widgets/band_identity_chip.dart`)
  - Inputs: a `BandSummary` (or its essential fields: id, name, logo URL, isPersonal) plus access to the authenticated user's avatar URL (read from auth state)
  - Renders `[avatar] [label]` with consistent sizing and spacing
  - Band gig: band logo (or colored initials fallback) + band name
  - Personal gig: user's avatar (or initials fallback) + the literal label "Personal"
  - Used by Dashboard cards, Bookings tab cards, and the booking-detail header

- **Create-booking sheet** (`features/bookings/widgets/create_booking_sheet.dart`)
  - Triggered by the "+" affordance on the Dashboard and Bookings tab
  - Top section: real bands the user is in (filtered: `isPersonal == false`), one row each, with band avatar + name
  - Visual divider
  - Bottom section: a single "Personal gig" row with the user's avatar and subtitle "Just for me, not tied to a band"
  - On tapping a real band: navigate to `/bookings/{bandId}/new`
  - On tapping "Personal gig":
    1. Show inline loading state on the row
    2. Call `personalBandProvider.ensureExists()`
    3. On success: close sheet, navigate to `/bookings/{personalBandId}/new`
    4. On failure: surface inline error in the sheet ("Couldn't set up personal gigs. Try again."), keep the sheet open
  - Edge case: when the user has zero real bands, the real-bands section is omitted and the sheet shows only the "Personal gig" row

#### Widgets (modified)

- **Dashboard cards** (`features/dashboard/widgets/event_card.dart` and any sibling card widgets) — render `BandIdentityChip` using each card's band data
- **Booking detail screen** — header / nav-bar uses `BandIdentityChip` instead of a hardcoded band name
- **Bookings tab screen** (`features/bookings/screens/bookings_screen.dart`) — fetches via the new multi-band provider, renders each row with `BandIdentityChip`. Layout stays as a list for v1 — the web's kanban is a richer surface that can be considered in a follow-up; converting to multi-band data and getting the visual identity right is enough scope for this spec.
- **Band selector screen** (`features/auth/screens/band_selector_screen.dart`) — filters out `isPersonal == true` bands from its list. Edge case: if the user's only band is personal, the router's existing single-band auto-select handles them; the selector screen never renders.

#### Booking form

The existing booking form is unchanged. It already accepts a band ID and operates against it. Personal gigs use the same form. Optional fields stay optional — a side gig can leave lineup, contracts, payment-groups, etc. blank without issue.

## User flows

### Flow A: First-time personal gig creation

1. User taps "+" on Dashboard (or Bookings tab)
2. Create-booking sheet opens. Real bands listed at top, divider, "Personal gig" row at bottom.
3. User taps "Personal gig"
4. Sheet shows loading on the row; mobile calls `POST /api/mobile/bands/solo`
5. Backend returns updated bands list including the new personal band; `authProvider` refreshes
6. `personalBandProvider.ensureExists()` resolves with the personal `BandSummary`
7. Sheet closes; router navigates to `/bookings/{personalBandId}/new`
8. User fills out the form (date, venue, name, optional pay, etc.) and saves
9. Booking persists. Dashboard + Bookings tab providers invalidate; the new gig appears in both with user's avatar + "Personal" label

### Flow B: Subsequent personal gig creation

Same as Flow A, except step 4–5 are skipped (personal band already in auth state). The sheet's "Personal gig" tap navigates immediately to `/bookings/{personalBandId}/new`.

### Flow C: Viewing a personal gig

1. User scrolls Dashboard or Bookings tab. Personal gigs render with user's avatar + "Personal" label; band gigs render with band avatar + band name.
2. Tap → existing booking detail screen opens. Header shows user's avatar + "Personal". All other fields and actions (edit, delete, payments, etc.) work normally.

### Flow D: Where the personal band is hidden vs. visible

| Surface | Treatment |
|---|---|
| Band selector screen (`/bands`) | Filtered out |
| Future band-switcher / chip UIs | Filtered out |
| Band settings / member management | N/A or filtered out (this spec doesn't add such UI) |
| "Create booking for [Band]" buttons | Filtered out (Personal has its own row) |
| Aggregated lists (Dashboard, Bookings tab) | Visible as items, rendered with personal treatment |
| Create-booking sheet | Special-cased: divider + "Personal gig" row |

### Flow E: Solo musician (only a personal band)

Already supported by existing code: `path_selection_screen.dart` offers "Go Solo" which calls `goSolo`, the router's single-band auto-select picks up the personal band, the user lands on the Dashboard. With this spec the experience continues to work — Dashboard shows their personal gigs, Bookings tab (`/me/bookings`) shows them too, the create-booking sheet shows just the "Personal gig" row.

## Error handling

- **`POST /bands/solo` failure during personal-gig creation.** Sheet shows inline error, stays open, allows retry. Backend is idempotent so retry is safe.
- **`/me/bookings` failure.** Standard error state on the Bookings tab — error message + retry. If cached data exists, show it with a stale indicator if that pattern exists elsewhere in the app.
- **`/bands/{id}/bookings` 403 on a personal band.** Shouldn't happen; defensively use the existing booking-detail error state.
- **Multiple personal bands per user.** Backend `goSolo` prevents this. If somehow it occurs, `personalBandProvider` picks the first; no further mitigation.
- **Card models without band info.** Cards whose feeding payload doesn't include band identity skip the chip rather than crash. Implementation plan verifies each card type and adds backend fields as needed.

## Testing

### Unit (Riverpod with `ProviderContainer`)

- `personalBandProvider.ensureExists()`:
  - Personal band already in auth state — no API call, returns it
  - Personal band missing, API succeeds — state updates, returns new band
  - Personal band missing, API fails — error propagates, state unchanged
- `BandSummary` parses `is_personal` correctly (true, false, missing)
- Booking model parses the new nested `band` field (and tolerates its absence if the backend hasn't been updated yet)

### Widget

- `BandIdentityChip`:
  - Non-personal band → band logo + band name
  - Non-personal band, no logo → initials fallback + band name
  - Personal band → user avatar + "Personal"
  - Personal band, no user avatar → initials fallback + "Personal"
- Create-booking sheet:
  - Renders real bands followed by divider and "Personal gig" row
  - Hides real-bands section when user has zero real bands
  - Tapping "Personal gig" calls `ensureExists()` and on success navigates with the right band ID
  - Tapping "Personal gig" on `ensureExists()` failure shows inline error
- Band selector screen filters out personal band

### Repository / integration

- `BookingsRepository.fetchAllForUser()` hits `/me/bookings`, parses pagination correctly
- Auth state refresh after `goSolo` updates the bands list and propagates to dependents

### Backend (Laravel)

- `/me/bookings` returns bookings across all user's bands (real and personal)
- `/me/bookings` paginates correctly
- `/me/bookings` includes the `band` object with `is_personal` on each item
- `/me/bookings` requires authentication; rejects unauthenticated requests

### Manual smoke tests

- First-time personal gig creation end-to-end
- Personal gig visible on Dashboard with user avatar + "Personal" label
- Personal gig visible in Bookings tab alongside band gigs
- Personal gig editable via existing booking detail
- Multi-band user: real bands + Personal all appear in create-booking sheet correctly
- Solo-only user: full flow works (path-selection → Go Solo → Dashboard → add gig → see it in Bookings tab)
- Multi-band user adding a personal gig: previously had only real bands; after adding their first personal gig, personal band silently appears in their auth state but stays hidden from band selectors

## Not changed

- `selectedBandProvider` — still backs Library, Finances, and band-scoped Dashboard sections
- `X-Band-ID` header on existing per-band requests
- Auth, login, signup, onboarding flows
- Booking form, detail, contacts, payments, contracts, history
- Library, Finances, Media, More tabs

## Decisions log

- **Personal gigs as bookings on `is_personal = true` band, not a separate entity:** maximum code reuse; the user never sees the wrapper.
- **No "Personal mode" toggle in global UI chrome:** matches the user's mental model — they think "side gig," not "switch to a different mode."
- **User's avatar (not a generic person icon) as the personal-gig identity:** matches the user's preference; reads as "you" rather than as another generic band.
- **Personal gigs visible on Bookings tab in v1, requiring multi-band conversion of that tab:** earlier discussion considered deferring the Bookings conversion, but a personal gig invisible to the Bookings tab would break the seamlessness goal.
- **`/me/bookings` aggregating endpoint instead of N parallel per-band calls:** matches the web's Bookings index pattern; one round trip; pagination is correct server-side.
- **Solo-musician path stays in scope:** existing onboarding already supports it; the spec verifies it continues to work end-to-end with the new visual treatment.
- **`selectedBandProvider` and `X-Band-ID` not removed:** removing the global single-band gate is a separate, larger reframe deferred to a future spec.
