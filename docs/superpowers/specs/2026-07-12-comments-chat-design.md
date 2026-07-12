# Comments & Chat — Design

**Date:** 2026-07-12
**Status:** Approved (pending implementation)
**Repos:** TTS (Laravel backend + web later), tts_bandmate (Flutter, first client)

## Goal

A single unified conversation system serving:

- **Comments** on events, rehearsals, and bookings (topic threads)
- **Member-to-member chat**: 1:1 DMs plus one built-in band group channel per band
- **Subs** can comment on events/rehearsals they are invited to, and can DM members of bands they sub for. Subs never see the band channel or booking threads.

Rollout: Laravel API + Flutter UI first; Vue web UI is a follow-up phase reusing the same endpoints.

## Data model (Laravel)

### `conversations`

| column | notes |
|---|---|
| `type` | `dm` \| `band` \| `topic` |
| `band_id` | nullable FK; set for `band` and `topic`, null for DMs |
| `conversable_type` / `conversable_id` | nullable polymorphic; `topic` only — `Events`, `Rehearsal`, or `Bookings` (mirrors `MediaAssociation`) |
| `dm_key` | nullable, unique; `"{lowUserId}:{highUserId}"` — one global DM per user pair |

- Unique: one `band` conversation per `band_id`; one `topic` per conversable.
- Band channels and topic threads are created lazily on first message/view. No backfill.
- **Canonicalization rule:** if a topic target is an `Events` row whose `eventable` is a `Rehearsal`, the conversation attaches to the `Rehearsal`. The event screen and rehearsal screen reach the same thread. Bookings are NOT canonicalized: a booking's thread is separate from its performance events' threads (different discussion contexts).

### `conversation_participants`

`conversation_id`, `user_id`, `last_read_at`; unique per (conversation, user).

- Powers unread counts, the badge, and read receipts ("seen by" = participants with `last_read_at` ≥ message `created_at`).
- DMs: both rows created with the conversation. Band/topic: row upserted lazily on first open; access is **derived** (policy), never stored.

### `messages`

`conversation_id`, `user_id`, `body` (nullable if images present), `edited_at`, soft-deletes, timestamps. Index `(conversation_id, id)`.

### `message_attachments`

`message_id`, `path`, `mime`, `width`, `height`, `size_bytes`.

- Images only in v1 (video/files deferred), up to 4 per message; a message carries text, images, or both.
- Client downscales/compresses before upload; server validates mime + size cap; stored on the same disk as the media feature.
- Served via an authenticated endpoint authorized by `ConversationPolicy` (no public URLs). Deliberately NOT reusing `MediaFile`/`MediaAssociation` — chat images must not appear in the band media library. "Promote to band media" is a possible future additive feature.

## Access & permissions (`ConversationPolicy`)

| type | who can view/post |
|---|---|
| `dm` | participants only. Starting a DM requires sharing ≥1 band (member↔member, member↔sub, sub↔member). |
| `band` | band owners + members. Subs excluded. |
| `topic` (event/rehearsal) | owners + members with `read:events`/`read:rehearsals`, **plus subs entitled to that specific event** via the existing `event_subs`/`event_members` entitlement join (`UserEventsService` pattern). A sub qualifies for a rehearsal if entitled to any `Events` row wrapping it. |
| `topic` (booking) | owners + members with `read:bookings`. Subs excluded (subs cannot read bookings anywhere). |

- **Moderation:** new team-scoped Spatie permission **`moderate:chat`**, grantable per-member in the member-permissions screen; owners implicitly have it. Allows deleting others' messages in band channels and topic threads. DMs are author-only, always. **Editing is always author-only.**
- Token abilities: `chat` added to `TokenService::buildAbilities()` resources. Band-scoped routes use the existing `mobile.band` middleware pattern; DM routes are band-agnostic (auth + policy only).

## API surface (all under `/api/mobile`)

- `GET /conversations` — DM + band-channel list with last-message preview + unread count
- `POST /conversations/dm` `{user_id}` — find-or-create global DM pair
- `GET /chat/contacts` — DM-able users (members of your bands; subs of your bands; for subs: members of bands they sub for)
- `GET /events/{key}/conversation`, `GET /rehearsals/{id}/conversation`, `GET /bookings/{id}/conversation` — resolve-or-create topic thread (canonicalizing), returns conversation + first message page
- `GET /conversations/{id}/messages?before={messageId}` — cursor pagination
- `POST /conversations/{id}/messages` — multipart: `body` and/or `images[]`
- `PATCH /messages/{id}` — author only; sets `edited_at`
- `DELETE /messages/{id}` — author or `moderate:chat`
- `POST /conversations/{id}/read` — bump `last_read_at` (badges + receipts)
- `POST /conversations/{id}/typing` — broadcast ephemeral typing event, nothing stored
- `GET /messages/{id}/attachments/{attachmentId}` — authenticated image serving

## Realtime

1. **Band-attached threads** (band channel + topics): `Message` uses the existing `BroadcastsBandChanges` trait → thin `{model:'message', parent: conversation}` signal on `private-band.{id}`. Flutter adds one switch case in `invalidationTargetsFor` (+ `_allRegisteredModels`) to refresh conversation lists/badges.
2. **DMs**: same thin signal on each participant's existing `App.Models.User.{id}` private channel. Flutter grows a small `userRealtimeProvider` mirroring the band one (same debounce/invalidation machinery, different channel).
3. **Open thread**: the active conversation screen subscribes to `private-conversation.{id}` — full message payloads on create/edit/delete for instant append (no refetch), plus typing events and read-receipt bumps. Follows the rehearsal-planner streaming pattern; channel authorized by `ConversationPolicy` in `routes/channels.php`.

Typing indicators go through the `POST /typing` endpoint (server-side broadcast), so no Pusher client-events setting is required.

## Push notifications

- Every message pushes to every participant except the author: DM → other person; band channel → all members; topic → everyone with access, including entitled subs.
- Data-only FCM via `SendUserPush`, dedupe key = message id, new `chat_message` push type routed in `push_route.dart` to the thread. App suppresses the local notification when that thread is open in the foreground.

## Flutter UI

- **Reusable thread widget** (bubbles, composer with image picker, typing indicator, "seen" receipts, edit/delete context menu), adapted from the rehearsal-planner screen.
- **Messages screen** at `/messages`: conversation list (avatars, previews, unread badges). Entry tile with badge in the More tab. Band channels appear automatically.
- **Event / rehearsal / booking detail screens**: "Comments" section at the end of the existing ListView — 2–3 most recent comments + unread-aware "View all" row pushing the full thread screen.
- Dark mode via `context.secondaryText` conventions.

## Testing

- Laravel feature tests covering the policy matrix: owner/member/sub × dm/band/topic(event, rehearsal, booking) × view/post/edit/delete/moderate; DM pair uniqueness; rehearsal canonicalization; attachment authorization.
- Flutter: `ProviderContainer` + fakes for providers (conversation list, thread, realtime invalidation case, user-channel binder); push-route unit test for `chat_message`.

## Deferred (explicitly out of v1)

- @mentions, arbitrary group chats, video/file attachments, promote-image-to-media, web (Vue) UI (phase 2), muting/notification preferences.

## Decisions log

- Unified conversation model over separate comments/chat systems (user: "same chat system").
- Chat shape: 1:1 DMs + one band group channel; no arbitrary groups.
- Subs: topic comments on entitled events/rehearsals + DMs; no band channel.
- DMs global per user pair, not band-scoped.
- Push everything (no mention-gating in v1).
- V1 features: delete own, edit own, unread badges, typing indicators, read receipts, image attachments, bookings commentable.
- Moderation: owner + new `moderate:chat` permission.
- Mobile first, then web.
