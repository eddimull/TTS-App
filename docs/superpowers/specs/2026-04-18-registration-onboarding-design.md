# Registration & Onboarding Design

**Date:** 2026-04-18  
**Status:** Approved

## Overview

Add account creation and post-registration onboarding to the mobile app. New users can register, then choose one of three paths: create a band, join an existing band, or go solo. Solo users get an invisible auto-band so all existing features work without a separate code path.

---

## Registration Screen

A new `SignUpScreen` with four fields: Full Name, Email, Password, Confirm Password. A "Create Account" primary button and a "Already have an account? Log in" link below.

On submit, calls `POST /api/mobile/auth/register`. The backend validates, creates the user, auto-applies any pending `Invitations` records matching the email (reusing existing logic from `RegisteredUserController`), issues a Sanctum token, and returns `{token, user, bands}` — the same shape as the login endpoint. The Flutter auth flow handles this identically to a login response.

The login screen gets a "Don't have an account? Sign up" link pointing to `SignUpScreen`.

---

## Choose Your Path Screen

Shown after registration, and also whenever the router's band-selection guard lands a user on `/bands` with zero bands (e.g., an existing user who isn't in any band yet).

Three large tappable cards:

- **Create a Band** → Create Band flow
- **Join a Band** → Join Band flow
- **Go Solo** → single tap, no further steps

This screen is also reachable from Settings so a solo user can join or create a band later.

---

## Create a Band Flow

**Step 1 — Name your band**  
Single text field for the band name. `site_name` is auto-generated on the backend (slugified, unique-checked server-side). Calls `POST /api/mobile/bands`. Returns the new band object.

**Step 2 — Invite members**  
Repeating email input. Each address added appears as a removable chip. "Skip for now" available at the bottom. Tapping "Done" or "Skip" calls `POST /api/mobile/bands/{band}/invite` for each email (reuses `InvitationServices::inviteUser()`), then navigates to the dashboard.

---

## Join a Band Flow

Three entry points, one outcome. All resolve via `POST /api/mobile/bands/join` with an invite `key`.

**Email link**  
The existing invitation email link gains a deep link scheme (e.g., `bandmate://invite/{key}`). Tapping on mobile opens the app. Two cases:
- *Not yet registered:* navigates to Sign Up with email pre-filled. On account creation, `POST /api/mobile/auth/register` auto-applies the pending invitation by email match (same logic as the web `RegisteredUserController`). No separate join call needed.
- *Already logged in:* calls `POST /api/mobile/bands/join` with the key directly.

**Invite code**  
A text input on the Join screen. The user types the code manually. Calls `POST /api/mobile/bands/join`. Available during onboarding (Join Band flow) and from Settings after onboarding.

**QR code**  
A "Scan QR" button opens the camera. The QR encodes the same invite key. Scanning resolves identically to entering the code manually. Band owners can view/share their QR from Settings → Band → Invite. `GET /api/mobile/bands/{band}/invite-qr` returns the raw invite key; the Flutter client renders the QR using `qr_flutter`.

`POST /api/mobile/bands/join` looks up the invitation by key, validates it's pending, adds the user to the band (owner or member per `invite_type_id`), marks the invite consumed (`pending = false`), and returns the updated bands list.

---

## Go Solo Flow

Tapping "Go Solo" calls `POST /api/mobile/bands/solo`. The backend:

1. Creates a `Bands` record named `"{Name}'s Band"` with an auto-slugified `site_name`
2. Creates a `BandOwners` record for the user
3. Sets `is_personal = true` on the band (new column)
4. Returns `{bands}` with the new band included

The Flutter app receives this like any other band response. The router's band-selection guard sees one band, auto-selects it, and navigates to the dashboard. No special UI branch is needed.

`is_personal` is available for future use (hiding the member roster, suppressing invite management) but is not acted on in this implementation.

---

## Backend Changes

### New migration

```
bands: add is_personal boolean default false
```

### New mobile API endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `POST` | `/api/mobile/auth/register` | Public | Create account, return `{token, user, bands}` |
| `POST` | `/api/mobile/bands` | Sanctum | Create a band, make user owner |
| `POST` | `/api/mobile/bands/{band}/invite` | Sanctum | Send email invites to members |
| `POST` | `/api/mobile/bands/join` | Sanctum | Accept invite by key |
| `GET` | `/api/mobile/bands/{band}/invite-qr` | Sanctum | Return invite key for QR rendering |
| `POST` | `/api/mobile/bands/solo` | Sanctum | Create personal auto-band |

### Reused backend logic

- `RegisteredUserController` invitation-matching (apply pending invites on register)
- `InvitationServices::inviteUser()` (send email invites)
- `BandOwners::create()` + `assignRole('band-owner')` (make user band owner)
- `BandMembers::create()` + `assignBandMemberDefaults()` (add member)

---

## Flutter Changes

### New screens

- `SignUpScreen` — registration form
- `PathSelectionScreen` — create / join / solo choice (replaces the current empty "no band" state)
- `CreateBandScreen` — band name + invite members (two-step)
- `JoinBandScreen` — code input + QR scanner

### Router updates

- Add `/signup` route
- Update `/bands` route to show `PathSelectionScreen` instead of the current placeholder
- Add deep link handler for `bandmate://invite/{key}`

### New providers / repositories

- `AuthRepository.register()` — calls `POST /api/mobile/auth/register`
- `BandsRepository` — `createBand()`, `inviteMembers()`, `joinBand()`, `goSolo()`, `getInviteKey()`

### Dependencies to add

- A Flutter QR code rendering package (e.g., `qr_flutter`) for displaying QR codes
- A QR scanner package (e.g., `mobile_scanner`) for scanning

---

## Out of Scope

- Editing band profile (name, location) — existing web app handles this
- Removing/leaving a band from mobile — future work
- Acting on `is_personal` in the UI (hiding roster, etc.) — future work
- Social sign-in (Google, Apple) — future work
