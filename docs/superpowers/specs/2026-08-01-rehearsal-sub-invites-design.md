# Rehearsal Sub Invites — Design

**Date:** 2026-08-01
**Repos:** tts_bandmate (Flutter) + TTS (Laravel backend)

## Summary

Band leaders can invite substitutes to an individual rehearsal from the rehearsal
schedule. Picking a sub attaches them immediately (no accept/decline step) and
notifies them by push and/or email. Invited subs see the rehearsal in their own
app view of the band.

## Decisions

- **Invite model:** assignment + notification. The sub is attached on pick; they
  get a push/email telling them they've been added. No pending/accept state.
- **Sub source:** the band's per-instrument substitute call lists, plus an ad-hoc
  invite-by-email form for people not on any list.
- **Entry points:** a Subs section on the rehearsal detail screen, and a
  long-press "Invite sub…" action on rehearsal rows in the schedule list.
- **Sub visibility:** invited subs see the rehearsal in their app (schedule list
  and read-only detail), not just the notification.
- **Storage:** a new dedicated `rehearsal_subs` table (not `event_members` reuse —
  the event machinery is slot-based and side-effect-heavy; rehearsals have no
  roster slots, and attendance tracking on rehearsals is out of scope).

## Backend (TTS, Laravel)

### Data model

New table `rehearsal_subs`, modeled on `event_subs` minus the invitation-key /
pending machinery:

| column | notes |
| --- | --- |
| id | |
| rehearsal_id | FK → rehearsals, cascade on delete |
| band_id | FK → bands |
| band_role_id | nullable FK — role context when picked from a call list |
| user_id | nullable FK — null for ad-hoc invitees with no account |
| name, email | required |
| phone, notes | nullable |
| invited_by | user id of the inviter |
| timestamps, deleted_at | soft deletes |

Constraints: unique `(rehearsal_id, user_id)`; ad-hoc invites deduped by
`(rehearsal_id, email)` in the service layer. Re-inviting a removed sub restores
the soft-deleted row (same restore trick as `RosterReconcileService::createEventMemberFor()`).

New model `RehearsalSub` (belongsTo Rehearsal, Bands, BandRole, User).
`Rehearsal` gains `hasMany(RehearsalSub)`.

Adding a registered sub also ensures a `band_subs` row exists (same side effect
as `SubInvitationService::inviteSubToEvent()`), so they appear in the band's
Substitutes screen.

### Endpoints

New `Api\Mobile\RehearsalSubsController`; writes gated on
`canWrite('rehearsals', $band->id)`:

- `POST /api/mobile/rehearsals/{rehearsal}/subs` — body is **either**
  `{call_list_entry_id}` (server resolves person + role from the
  `substitute_call_lists` entry) **or** `{name, email, phone?, band_role_id?}`
  for ad-hoc.
- `DELETE /api/mobile/rehearsals/{rehearsal}/subs/{sub}`

No new GET endpoints:

- The picker reuses the existing call-lists endpoint
  (`GET /api/mobile/bands/{band}/subs/call-lists`).
- The invited-subs list rides in the rehearsal detail payload:
  `Mobile\RehearsalService::formatDetail()` gains a `subs` array —
  `{id, name, email, phone, band_role_id, role_name, user_id, is_registered}`.

**Virtual rehearsals:** no new by-key endpoints. The existing
`GET /api/mobile/rehearsals/by-key/{key}` already materializes a stub via
`RehearsalService::findOrCreateStub()` and returns its id; the app resolves
virtual rows to a real id first, then uses the id-based sub endpoints.

### Notifications

Every invited sub receives an email; registered subs with the app additionally
get a push.

- `ProcessRehearsalSubAdded` job, modeled on `ProcessRehearsalCancelled`:
  - Email (all invitees, always): new mailable `RehearsalSubAdded` with band,
    date/time, venue, notes.
  - Push (registered subs with device tokens): `SendUserPush`
    (`type: 'rehearsal_sub_added'`, `rehearsalId`, date; tap deep-links to
    rehearsal detail).
- Removal sends a matching "no longer needed" push/email
  (`ProcessRehearsalSubRemoved`, `type: 'rehearsal_sub_removed'`).
- `ProcessRehearsalCancelled` is extended to also notify the rehearsal's
  invited subs, not just `$band->everyone()`.

### Sub visibility

When the requesting user is a sub of the band (not a full member):

- `schedules()` returns only rehearsals where they have a live `rehearsal_subs`
  row — no virtual expansion, no full schedule.
- `show()` / `showByKey()` allow read-only access to a rehearsal they're
  invited to.
- The invited-rehearsals query is keyed by `user_id` and band-scoped, so it does
  not depend on token ability flags (avoids the known band-agnostic-abilities
  leak).

## Flutter app (tts_bandmate)

### Data layer

- New model `RehearsalSub` (`id, name, email, phone, bandRoleId, roleName,
  userId, isRegistered`), hand-written `fromJson` per repo convention.
- `RehearsalDetail` gains `subs: List<RehearsalSub>`.
- `RehearsalsRepository` gains `addSub(rehearsalId, {callListEntryId | name,
  email, phone, bandRoleId})` and `removeSub(rehearsalId, subId)`.
- New endpoint constants in `api_endpoints.dart`.

### UI

- **Rehearsal detail screen** (`rehearsal_detail_screen.dart`): a "Subs"
  section after the info rows — invited subs (name, role badge, swipe or
  long-press to remove) and an "Invite Sub" button. Shown only for users with
  write access (same gating as notes editing). Read-only for subs viewing a
  rehearsal they're invited to.
- **Picker sheet**: modeled on the event `_SubPickerSheet`, but since rehearsals
  have no slots it lists the band's call lists grouped by instrument (data from
  the existing `callListsProvider`), plus an "Invite by email…" row opening a
  small name/email/phone/optional-role form (pattern from `InviteSubSheet`).
- **Schedule list** (`rehearsals_screen.dart`): long-press on a rehearsal row →
  "Invite sub…" context action. Virtual rows resolve via the existing by-key
  fetch (which materializes the rehearsal), then open the same picker.

### State

Invited subs live on `rehearsalDetailProvider`; after add/remove the provider
refreshes the detail. No separate subs provider family needed.

## Edge cases

- Duplicate invite → 422 with a friendly "already invited" message.
- Inviting to a cancelled or past rehearsal → blocked with a clear message.
- Removing a sub restores cleanly on re-invite (soft-delete restore).
- Ad-hoc invitee later registers: out of scope for v1 (their `rehearsal_subs`
  row keeps `user_id` null; linking on registration is a follow-up).

## Testing

- **Backend feature tests:** invite from call list entry, ad-hoc invite,
  duplicate/dedupe/restore, permission gating (non-writer 403), sub-only
  schedule visibility, read-only sub detail access, cancellation notifies
  invited subs, cancelled/past rehearsal blocked.
- **Flutter:** unit tests for model parsing, repository methods, and provider
  behavior using the existing `ProviderContainer` + fake patterns. UI verified
  on-device.

## Out of scope

- Accept/decline flow for invites.
- Attendance tracking on rehearsals (for members or subs).
- Payout amounts for rehearsal subs.
- Auto-linking ad-hoc invitees who register later.
