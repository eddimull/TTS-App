# Chat polish: media viewer, reactions, timestamps & delivery status

**Date:** 2026-07-18
**Repos:** tts_bandmate (Flutter mobile) + TTS (Laravel backend)
**Status:** Approved design

## Problem

Chat works but is barebones:

- Shared pictures render inline only — no fullscreen view, no way to save or
  share them.
- No emoji reactions on messages.
- No visible timestamps; message status is limited to a bare "Seen" label on
  the last own message.

## Goals

1. Tap a picture to view it fullscreen; save it to the photo library or share
   it via the system sheet.
2. React to any message with a quick set of 6 emoji tapbacks.
3. See when messages were sent (date separators + tap-to-reveal exact time).
4. See delivery/read status: iMessage-style "Delivered" / "Seen <time>" in
   DMs, "Seen by N" in group chats.

## Non-goals

- Full emoji picker for reactions (quick set only; extensible later).
- Video attachments (chat uploads are images only today).
- Per-message delivery ticks in group chats (WhatsApp style) — groups show
  seen-aggregation on the newest own message only.
- Guaranteed lock-screen delivery acks: a device acks delivery only when the
  app actually processes messages (foreground, thread fetch, or realtime
  receipt). "Delivered" means "their app has received it".

## Phasing

Three independently shippable phases. Each phase: fresh branch (`main` for
mobile, `staging` for TTS), separate PRs per repo, Copilot review addressed,
on-device verification before done.

| Phase | Scope | Repos |
|-------|-------|-------|
| 1 | Fullscreen viewer + save/share + timestamps | mobile only |
| 2 | Emoji reactions | TTS + mobile |
| 3 | Delivered/seen status | TTS + mobile |

---

## Phase 1 — Media viewer + timestamps (mobile only)

### Fullscreen viewer

- Tapping an attachment in `_MessageBubble` pushes a fullscreen
  black-background route.
- `PageView` swipes between the tapped message's attachments (initial page =
  tapped attachment); `InteractiveViewer` provides pinch-zoom/pan per page.
- Image bytes come from the existing authenticated endpoint
  `GET /api/mobile/messages/{message}/attachments/{attachment}`, which serves
  the original full-res binary. Bytes are fetched once per attachment and
  shared between display, save, and share.
- Top-right actions:
  - **Save** — write to the photo library via the `gal` package. Requires
    `NSPhotoLibraryAddUsageDescription` in iOS Info.plist. Success shows a
    brief confirmation; permission denial shows an alert pointing at
    Settings.
  - **Share** — `share_plus` system share sheet with the image file (user can
    AirDrop, save, forward, etc.).
- Error handling: fetch failure shows a retry affordance inside the viewer;
  save/share failures surface a Cupertino alert.

### Timestamps

- **Date separators**: a centered separator row is inserted between two
  messages when the calendar day changes **or** the gap exceeds 1 hour.
  Format: "Today 3:42 PM", "Yesterday 9:10 AM", weekday + time within the
  last 7 days, full date + time older.
- **Tap-to-reveal**: tapping a bubble toggles a small exact-time label under
  it. The existing "edited" marker merges into this revealed line
  ("3:42 PM · edited").
- Separator/label formatting is a pure function (message list → separator
  positions + labels) with unit tests; tests pin the clock (no live `now()`
  assertions).

### New dependencies

`gal`, `share_plus` (both mobile).

---

## Phase 2 — Emoji reactions (TTS + mobile)

### Wire contract (frozen)

**Table** `message_reactions`:

| column | type |
|--------|------|
| id | pk |
| message_id | fk → messages, cascade delete |
| user_id | fk → users |
| emoji | string |
| timestamps | |

Unique index on `(message_id, user_id, emoji)`.

**Endpoints** (participant-only authorization, same guard as message read):

- `POST /api/mobile/messages/{message}/reactions` body `{"emoji": "👍"}` —
  idempotent add.
- `DELETE /api/mobile/messages/{message}/reactions/{emoji}` — idempotent
  remove.
- Both return the message's updated aggregated `reactions` array.

**Message JSON** gains:

```json
"reactions": [{"emoji": "👍", "count": 3, "user_ids": [1, 5, 9]}]
```

Client derives "I reacted" and reactor names from `user_ids` + participants.

**Realtime**: reaction add/remove fires the existing
`ConversationStreamEvent` broadcast so open threads update live.

### Mobile UI

- Quick set: 👍 ❤️ 😂 😮 😢 🎉
- Long-press any non-deleted message (own or others') opens the action
  sheet, now with an emoji row at the top. The existing own/moderator gate
  moves off the sheet as a whole and onto just the Edit/Delete actions.
- Your active reactions are highlighted in the row; tapping toggles.
- Reaction chips (emoji + count) render under the bubble; a chip containing
  your reaction is tinted. Tapping a chip toggles your reaction.
- Optimistic update with rollback on API failure.

### Tests

Backend feature tests: add, remove, toggle idempotency, authorization,
aggregation shape, broadcast fired. Mobile unit tests: reaction toggle state
transitions, chip aggregation from `user_ids`.

---

## Phase 3 — Delivered/seen status (TTS + mobile)

### Backend

- Migration: `last_delivered_at` (nullable timestamp) on
  `conversation_participants`.
- `POST /api/mobile/conversations/delivered` — bulk ack: sets
  `last_delivered_at = now()` on **all** the authenticated user's participant
  rows. Semantics: "my app has received everything up to now".
- Participants JSON gains `last_delivered_at`.
- Ack broadcasts a participant update on affected conversation channels,
  mirroring the existing read-receipt broadcast path.

### Mobile ack triggers

- Conversations list fetch (app open / foreground refresh).
- Realtime message received while the app is running.

### Display (under your newest own message)

- **DM**: "Delivered" once the other participant's `last_delivered_at` ≥ the
  message's `created_at`; upgrades to "Seen 3:42 PM" from their
  `last_read_at`.
- **Group**: "Seen by N" (count of other participants whose `last_read_at` ≥
  message `created_at`); tapping shows the names.
- Derivation is a pure function `(message, participants) → status` with unit
  tests (clock pinned).

---

## Cross-cutting decisions

- Hand-written `fromJson` factories with null-safe coalescing, matching the
  existing models — no codegen.
- Cupertino widgets throughout; text colors via `context.secondaryText` /
  `context.tertiaryText` extensions, never raw `CupertinoColors.*Label`.
- Backend work is implemented via the `laravel-mobile-api-dev` agent; all
  php/artisan/composer commands run inside the app container.
- TTS PRs target `staging` (auto-deploys on merge); mobile PRs target `main`.
