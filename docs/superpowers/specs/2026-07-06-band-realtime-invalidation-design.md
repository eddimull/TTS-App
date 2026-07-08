# Band-scoped realtime invalidation — design

**Date:** 2026-07-06
**Repos:** TTS (Laravel backend) + tts_bandmate (Flutter mobile)
**Status:** Approved

## Problem

Data changed by one band member (or by the web app) goes stale on other members'
mobile screens until they manually refresh. We want every band-scoped model's
create/update/delete pushed to band members' devices in real time, with one
generic mechanism rather than per-model one-offs.

**Driving use case:** an upcoming comments/discussion feature (no comments
model exists in either repo yet). This realtime layer is its foundation; the
comments feature itself (data model, API, UI) is a separate spec. A future
`Comment` model joins the mechanism with one `use` line plus a
`broadcastParent()` override pointing at its commentable.

## Decisions made

- **Scope:** all band-scoped models, one generic mechanism (not per-feature).
- **Payload:** thin signal `{model, id, action}` → client refetches through the
  normal API. No model serialization on the broadcast path.
- **Backend wiring:** opt-in `BroadcastsBandChanges` model trait (explicit,
  greppable), not a global wildcard listener and not Laravel's stock
  `BroadcastsEvents` (which is geared to per-instance channels + full payloads).

## Backend (TTS repo)

### Event

`App\Events\BandDataChanged` implements `ShouldBroadcast` (queued via Horizon —
a broadcast failure or queue lag must never block or slow the originating
write).

- Channel: `PrivateChannel('band.{bandId}')`
- `broadcastAs()`: `band.data-changed`
- Payload: `{ "model": "booking", "id": 123, "action": "created" }`
  - `model` is a stable short name (snake-case class basename), `action` is one
    of `created` / `updated` / `deleted`.
  - Optional `parent: { "model": "...", "id": ... }` for child models whose
    client-side providers are keyed by their parent (a comment's thread is
    fetched by booking id, an event member by event id). Supplied by an
    overridable trait method (e.g. `broadcastParent()`), omitted by default.

### Trait

`App\Models\Concerns\BroadcastsBandChanges`:

- `bootBroadcastsBandChanges()` registers `created` / `updated` / `deleted`
  model-event hooks that dispatch `BandDataChanged`.
- Band resolution: `broadcastBandId()`, defaulting to `$this->band_id`.
  Models that reach the band indirectly override it (e.g. `EventMember` via its
  event). If it resolves to null, skip silently — never throw from the hook.
- Applied per model with one `use` line. Initial set: `Bookings`, `Events`,
  `Rehearsals`, `Roster`, `EventMember`, extended by a sweep of band-scoped
  models during implementation.

Known blind spot: raw DB-level cascade deletes don't fire Eloquent events. The
existing observer-driven cascades (e.g. booking deletion deleting events in
`BookingObserver`) DO fire them, so the core models are covered.

### Channel auth

One entry in `routes/channels.php`: `band.{bandId}` authorizes iff the user is
a member of that band (same shape as the existing `setlist.{sessionId}` check).
Broadcast auth already runs under `auth:sanctum` at `/broadcasting/auth`, which
the mobile authorizer already uses.

Permission note: the thin signal leaks only "model X id N changed" to all band
members. Actual data is fetched through the API, which enforces per-ability
permissions — finance-restricted subs receive a signal they can't act on, not
data.

## Mobile (tts_bandmate repo)

### Shared connection service (small refactor, in scope)

`PusherChannelsFlutter.getInstance()` is a singleton and the live-setlist
feature already `init()`s it. Extract a shared connection service in `core/`
that owns init/connect and hands out subscribe/unsubscribe, then port the
live-setlist provider to it so neither feature resets the other's connection.
This is the only refactor in scope.

### Realtime provider + invalidation registry

`bandRealtimeProvider` (in `shared/providers/`):

- Watches selected band + auth token; subscribes to `private-band.{id}` using
  the existing `pusherAuthorizer`; unsubscribes on band switch / logout.
- Incoming `band.data-changed` events go through a registry mapping model name
  → providers to invalidate (e.g. `booking` → bookings list +
  `bookingDetail(id)` family member). When the signal carries `parent`, the
  registry keys family invalidation off `parent.id` (e.g. `comment` →
  `commentsFor(parent.id)`).
- Per-model debounce (~300 ms) so a burst (roster sync touching 20 events)
  causes one refetch, not 20.

### Resilience

- Sockets die on app background. Signals are pure invalidation, so no replay is
  needed: on reconnect / app resume, blanket-invalidate the band-scoped
  providers once.
- Horizon or the socket broker being down degrades to exactly today's
  behavior: stale until manual refresh.
- The writer receives its own signal (self-refetch). Harmless; suppressing it
  (`broadcast(...)->toOthers()` + Dio sending `X-Socket-ID`) is a cheap
  follow-up, explicitly out of v1.

## Production constraint

Prod realtime for mobile is currently broken: soketi serves the socket but
`pusher_channels_flutter` can only reach `ws-<cluster>.pusher.com`. The known
fix (already identified for planner chat) is real Pusher Cloud creds with
`PUSHER_HOST` left blank. This feature works on local soketi immediately and
rides on that switch for prod. Thin signals count against Pusher Cloud message
quotas (free tier ~200k msgs/day) — fine at current scale.

## Testing

- **Backend:** `Event::fake()` tests asserting `BandDataChanged` (correct
  channel, model, id, action) fires on create/update/delete of a representative
  model; channel-auth test (member authorized, non-member rejected); trait test
  for the indirect `broadcastBandId()` override and the null-band skip.
- **Mobile:** unit tests for the registry mapping and debounce against a fake
  connection service; existing live-setlist tests must stay green after the
  connection-service refactor.

## Out of scope

- `toOthers()` / `X-Socket-ID` sender suppression (follow-up).
- Full-payload push for hot models (revisit only if refetch latency is felt).
- The prod Pusher Cloud switch itself (existing, separately tracked fix).
- Web (Echo) consumers — web already has its own realtime usage; this adds no
  web work, though it can subscribe to the same channel later.
