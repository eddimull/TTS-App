# Band Settings — Phase 1: Band Info & Basic Member Management

**Date:** 2026-04-20
**Status:** Approved
**Scope:** Phase 1 of 3. Covers band info editing, member management with granular permissions, invitation management, and QR invite. Phases 2 (roles/rosters/sub-lists) and 3 (permissions UI overhaul + calendar config) follow separately.

---

## Overview

Add a "Band Settings" section to the mobile app, accessible only to band owners. Owners can edit band info, manage members with per-feature permission toggles, manage pending invitations, and invite new members via email or QR code.

Entry point: an owner-only "Band Settings" tile in the More screen. Non-owners never see it.

---

## Navigation & Entry Point

- More screen gains a conditional `Band Settings` list tile, rendered only when the current user is a band owner (`isOwner` flag from the existing `AuthState`)
- Tapping pushes `BandSettingsScreen` — a scrollable Cupertino grouped list with four sections
- Child screens push onto the same navigator stack (no nested tab bar)

---

## Screen: BandSettingsScreen

Four grouped sections:

### Section 1 — Band Info

Static display of current band name and logo. Tapping "Edit" pushes `BandInfoEditScreen`.

### Section 2 — Members

List of current band members. Each row: avatar initials, display name, Owner/Member badge.

- **Swipe-to-delete** triggers a `CupertinoAlertDialog` confirmation, then calls `DELETE /api/mobile/bands/{band}/members/{user}`. On success, removes from local state.
- **Tapping a row** pushes `MemberPermissionsScreen` for that member.

### Section 3 — Invitations

List of pending invitations. Each row: email address, invite type (Owner / Member).

- **Swipe-to-delete** revokes the invitation (`DELETE /api/mobile/bands/{band}/invitations/{invitation}`) after a confirmation alert. On success, removes from local state.

### Section 4 — Invite

A `CupertinoListTile` that expands in-place (disclosure group) to reveal:

- Email text field
- Owner / Member segmented control
- Send button → `POST /api/mobile/bands/{band}/invite`; on success, appends the new invite to the invitations list and collapses the section
- QR code rendered via `qr_flutter` using the band's current invite key (`GET /api/mobile/bands/{band}/invite-qr` — already exists). Tapping the QR enlarges it in a modal sheet with a Share button.

---

## Screen: BandInfoEditScreen

Form with fields:

- **Band Name** (text field, required)
- **Page URL** (`site_name`, text field, required — server validates uniqueness)
- **Address** — Street, City, State, Zip (four separate fields)
- **Logo** — tappable avatar; opens image picker (`image_picker`), uploads via `POST /api/mobile/bands/{band}/logo`. Shows upload progress indicator inline; reverts on failure.

Save calls `PATCH /api/mobile/bands/{band}`. Server-side validation errors are surfaced inline on the relevant field. On success, pops back to `BandSettingsScreen` with updated state.

---

## Screen: MemberPermissionsScreen

Shown when tapping a member row. Displays the member's name and badge at the top.

**Owners:** All 9 permission pairs shown as locked-on (disabled toggles, no interaction).

**Members:** 9 read/write toggle pairs, one row per resource:

| Resource | Read toggle | Write toggle |
|---|---|---|
| Events | ✓ | ✓ |
| Bookings | ✓ | ✓ |
| Rehearsals | ✓ | ✓ |
| Charts | ✓ | ✓ |
| Songs | ✓ | ✓ |
| Media | ✓ | ✓ |
| Invoices | ✓ | ✓ |
| Proposals | ✓ | ✓ |
| Colors | ✓ | ✓ |

Each toggle is **optimistic**: flips immediately on tap, calls `PATCH /api/mobile/bands/{band}/members/{user}/permissions` with `{permission, granted}`. On API failure, reverts the toggle and shows a `CupertinoAlertDialog` with the error.

Permission names map directly to Spatie permission strings: `read:events`, `write:events`, etc.

---

## Backend: New Mobile API Endpoints

All routes are under the existing Sanctum-authenticated mobile middleware group. All require the requesting user to be a band owner (enforced via the existing `owner` middleware or a new `EnsureUserIsOwner` middleware).

| Method | Path | Purpose | Backend reuse |
|---|---|---|---|
| `GET` | `/api/mobile/bands/{band}` | Fetch band detail (name, site_name, address, logo_url) | `Bands` model |
| `PATCH` | `/api/mobile/bands/{band}` | Update name, site_name, address | Existing web `update()` logic |
| `POST` | `/api/mobile/bands/{band}/logo` | Upload and store band logo | Existing `uploadLogo()` logic |
| `GET` | `/api/mobile/bands/{band}/members` | List members with is_owner flag and current permissions | `Bands::everyone()`, Spatie permissions |
| `DELETE` | `/api/mobile/bands/{band}/members/{user}` | Remove a member | `BandMemberRemovalService` |
| `PATCH` | `/api/mobile/bands/{band}/members/{user}/permissions` | Grant or revoke a single permission | `$user->givePermissionTo()` / `revokePermissionTo()` with `setPermissionsTeamId($band->id)` |
| `GET` | `/api/mobile/bands/{band}/invitations` | List pending invitations | `Bands::invitations()->where('pending', true)` |
| `DELETE` | `/api/mobile/bands/{band}/invitations/{invitation}` | Revoke a pending invitation | Set `pending = false` or delete record |
| `POST` | `/api/mobile/bands/{band}/invite` | Send email invite (owner or member) | Already exists — `OnboardingController::inviteMembers()` |
| `GET` | `/api/mobile/bands/{band}/invite-qr` | Get invite key for QR rendering | Already exists — `OnboardingController::inviteQr()` |

---

## Flutter Architecture

### New feature slice: `lib/features/band_settings/`

```
band_settings/
├── data/
│   ├── models/
│   │   ├── band_detail.dart         # name, site_name, address, logo_url
│   │   ├── band_member.dart         # id, name, is_owner, Map<String,bool> permissions
│   │   └── band_invitation.dart     # id, email, invite_type ('owner'|'member'), key
│   └── band_settings_repository.dart
├── providers/
│   └── band_settings_provider.dart  # AsyncNotifier holding detail + members + invitations
└── screens/
    ├── band_settings_screen.dart
    ├── band_info_edit_screen.dart
    ├── member_permissions_screen.dart
    └── widgets/
        └── invite_section.dart      # expandable invite form + QR code
```

### New API endpoint constants (api_endpoints.dart)

```dart
static String mobileBandDetail(int bandId) => '/api/mobile/bands/$bandId';
static String mobileBandLogo(int bandId) => '/api/mobile/bands/$bandId/logo';
static String mobileBandMembers(int bandId) => '/api/mobile/bands/$bandId/members';
static String mobileBandMember(int bandId, int userId) => '/api/mobile/bands/$bandId/members/$userId';
static String mobileBandMemberPermissions(int bandId, int userId) => '/api/mobile/bands/$bandId/members/$userId/permissions';
static String mobileBandInvitations(int bandId) => '/api/mobile/bands/$bandId/invitations';
static String mobileBandInvitation(int bandId, int invitationId) => '/api/mobile/bands/$bandId/invitations/$invitationId';
```

### Router

Add `/band-settings` route under the authenticated shell. Owner-only guard in the router redirect: if current user is not owner of the selected band, redirect to `/dashboard`.

### State management

`BandSettingsNotifier` (AsyncNotifier) holds:
- `BandDetail` — loaded once on screen open
- `List<BandMember>` — members with permissions
- `List<BandInvitation>` — pending invitations

Optimistic updates for permission toggles: flip in local state immediately, revert on API error. Member removal and invite revocation remove from local list on success.

### Dependencies

- `image_picker` — already in project (verify); used for logo selection
- `qr_flutter` — already added during onboarding phase; used for invite QR

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Permission toggle failure | Revert toggle, show `CupertinoAlertDialog` with server error message |
| Member removal failure | Show inline error, member remains in list |
| Invite revocation failure | Show inline error, invitation remains in list |
| Band info save — validation error | Surface server message inline on the offending field |
| Logo upload failure | Show toast, avatar reverts to previous state |
| 401 on any call | Falls through to existing `OnUnauthorized` handler → `/login` |

---

## Testing

- Unit tests for `BandSettingsRepository`: happy path + 4xx for each endpoint, using a fake Dio/HTTP client
- Unit tests for `BandSettingsNotifier`: optimistic toggle revert, member removal from local state, invite append on send success
- No widget tests (consistent with current project test approach)

---

## Out of Scope (Phase 1)

- Band roles, rosters, sub-lists — Phase 2
- Per-member calendar access configuration — Phase 3
- External calendar connections — Phase 3
- Stripe account setup — deferred (web handles it; no mobile equivalent planned yet)
- Leaving a band (member-initiated) — future work
- Deleting a band — future work
- Acting on `is_personal` flag in member management UI — future work
