# Rehearsal Cancel/Restore from Mobile — Design

**Date:** 2026-07-04
**Repos:** `tts_bandmate` (Flutter, branch off `main`) + `TTS` (Laravel, branch off `staging`)

## Problem

There is no way to mark a rehearsal as cancelled from the mobile app — in particular a
single occurrence of a recurring rehearsal schedule. The web UI has a
`toggle-cancelled` action; mobile already *renders* cancelled state (strikethrough in
the schedules list, banner on the detail screen) but has no way to set it. Band members
also get no notification when a rehearsal is called off.

## Decisions (from brainstorming)

- **Cancel semantics:** the occurrence stays on the calendar, shown struck-through with
  a "Cancelled" badge. No delete/remove-from-calendar action.
- **Reversible:** mobile can also restore (un-cancel) a cancelled rehearsal.
- **UI placement:** rehearsal detail screen only. No list long-press/swipe actions.
- **Notifications:** in-app (database) + email + push to all band members when a
  rehearsal is cancelled or restored, excluding the actor.
- **Push is built as a generic band-push layer**, not a rehearsal one-off — a planned
  event-discussion/chat feature will be its next consumer.
- **Versioning:** no manual bump. release-please cuts **1.10.0** automatically from
  `feat:` commits merged to `main` (config has `bump-minor-pre-major`), independent of
  1.9.0 currently in app-store review.

## How recurrence already works (context)

- `rehearsal_schedules` is the series definition; occurrences are computed virtually at
  read time (`RehearsalScheduleService`) and materialized to a real `rehearsals` +
  `events` row on demand (`Mobile\RehearsalService::findOrCreateStub`, hit by the
  mobile `by-key` endpoint when opening a virtual occurrence).
- `rehearsals.is_cancelled` (boolean) already exists; the virtual-occurrence generator
  already skips dates that have a materialized row, so a cancelled occurrence
  suppresses regeneration of its slot for free.
- Consequence: by the time the mobile detail screen is open, the occurrence always has
  a real integer id. Cancel is a simple PATCH by id — no virtual-key handling needed.

## Backend (TTS)

### Endpoint

`PATCH /api/mobile/rehearsals/{rehearsal}/cancelled` with body `{"is_cancelled": true|false}`.

- Explicit set, not toggle: idempotent, retry-safe, and maps directly onto
  "Cancel"/"Restore" UI copy. The web `toggle-cancelled` route is untouched.
- New `setCancelled()` action on `Api\Mobile\RehearsalsController`, gated
  `canWrite('rehearsals', $band)` exactly like `updateNotes()`.
- Response: the refreshed detail payload from the existing
  `RehearsalService::formatDetail` (same shape the detail screen already consumes).
- Route registered in `routes/api.php` alongside the notes route.
- No migration — the column exists.
- Only fire notifications when the value actually changes (setting `true` on an
  already-cancelled rehearsal is a no-op success).

### In-app + email notification

- New queued job `ProcessRehearsalCancelled` (pattern: `ProcessEventUpdated`),
  dispatched from `setCancelled()` on a real state change, carrying rehearsal id,
  actor id, and the new state.
- The job iterates `$band->everyone()` and calls `$user->notify(...)` per member,
  skipping the actor.
- New notification class `RehearsalCancelled` (pattern: `TTSNotification`):
  `via()` returns `['database']` plus `'mail'` when `$notifiable->emailNotifications`.
  Copy distinguishes cancelled vs restored ("Rehearsal on {date} was cancelled" /
  "Rehearsal on {date} is back on"), links to the rehearsal.
- The same job also dispatches the push sends (below) per eligible member, so
  recipients/exclusions are resolved in one place.

### Generic push layer (refactor)

Current state: `SendEventPush` job bundles token lookup, `FcmSender` send, dead-token
pruning, and `PushNotificationLog` idempotency, but is shaped around leave-by event
reminders. Refactor:

- New generic job `SendUserPush(User $user, array $data, string $dedupeKey)` containing
  the token/send/prune/log machinery. `PushNotificationLog` idempotency keys on
  (user, dedupeKey) — adjust the table/model minimally if its current columns are
  event-reminder-specific.
- `LeaveByPushService` / `SendEventPush` callers are rewired onto `SendUserPush`
  (leave-by behavior unchanged — covered by its existing tests).
- Rehearsal cancel/restore is the second caller: dedupe key like
  `rehearsal_cancelled:{rehearsalId}:{is_cancelled}:{updated_at}` so re-cancelling
  after a restore still notifies but retries don't double-send.
- Recipients: band members (`$band->everyone()`) who have device tokens, minus actor.

### Push payload contract

**Delivery amendment (from implementation planning):** rehearsal pushes are sent as
**notification+data hybrid** FCM messages, not data-only. The mobile app's background
FCM handler is a Phase-1 no-op, so a data-only message never displays when the app is
backgrounded or terminated — the common case for a cancellation. A hybrid message is
OS-rendered in those states on both platforms. Leave-by reminders remain data-only
(unchanged). The `data` map contract below applies to both kinds.

Every push the backend sends carries:

| Key | Required | Purpose |
| --- | --- | --- |
| `type` | yes | Machine type, e.g. `rehearsal_cancelled`, `rehearsal_restored`, existing `event_reminder_8h` / `event_departure`, future `event_chat_message` |
| `title` | yes | Display-ready notification title |
| `body` | yes | Display-ready notification body |
| *(type-specific)* | no | Routing keys — here `rehearsalId`, `date` |

Rule: a client that doesn't know a `type` can still render the notification from
`title`/`body`. New types never require a mobile release to display, only to deep-link.
(Existing leave-by sends are updated to include `body` so they conform.)

### Backend tests

- Feature tests for the endpoint: cancel, restore, idempotent re-cancel (no duplicate
  notifications), permission denial for read-only member, cross-band 404,
  unauthenticated 401.
- Notification job test: all members minus actor notified, email gated on
  `emailNotifications`, push dispatched only to members with device tokens.
- `SendUserPush` unit test (send/prune/dedupe) + existing leave-by tests stay green
  after the rewire.

## Mobile (tts_bandmate)

### Cancel/restore UI

- `rehearsals_repository.dart`: `setCancelled(int id, bool isCancelled)` returning the
  updated `RehearsalDetail`; new constant in `api_endpoints.dart`.
- Detail screen (`rehearsal_detail_screen.dart`):
  - Upcoming, not cancelled → "Cancel rehearsal" action (destructive styling) behind a
    confirmation `CupertinoActionSheet`.
  - Cancelled → "Restore rehearsal" action on/near the existing cancellation banner
    (simple confirm dialog).
  - On success: refresh the detail provider and invalidate the schedules provider and
    dashboard/events providers so list strikethrough and calendar update immediately.
  - In-flight state disables the action; failures surface the standard error toast.
- Past rehearsals: no cancel action (nothing to call off).

### Push generalization

- `push_payload.dart`: add `rehearsalCancelled` / `rehearsalRestored` types and a
  generic fallback — any data-only message with `title` + `body` renders those verbatim
  even when `type` is unknown (today unknown types render a hardcoded "Event today"
  title, which would be wrong for non-event pushes).
- `push_service.dart`: render non-reminder pushes on a new Android channel
  `band_updates` ("Band updates"); leave-by reminders keep `event_reminders`.
- Tap on a `rehearsal_cancelled`/`rehearsal_restored` notification deep-links to
  `/rehearsals/{rehearsalId}`.

### Mobile tests

- Repository test for `setCancelled` (endpoint, body, parse).
- Provider/notifier test: state refresh + invalidation on success, error propagation.
- Widget test: confirm-sheet flow — cancel action shows sheet, confirming calls the
  repository, UI flips to cancelled banner with restore action.
- `PushPayload` tests: new types parse, unknown type with title/body renders generic,
  notification-id stability.

## Rollout / ordering

1. Backend PR to `staging` (endpoint + notifications + push refactor) — deployable
   alone; merging auto-deploys staging.
2. Mobile PR to `main` (UI + push handling) — degrades gracefully against an older
   backend only in that cancel would 404; in practice backend lands first.
3. release-please releases mobile as 1.10.0.

## Out of scope

- Deleting occurrences or whole series; "this and all future" cancellation.
- Cancelling from the list (long-press/swipe).
- Push opt-out preferences (eligibility remains "has a device token").
- The event discussion/chat feature itself (this design only leaves the push layer
  generic for it).
