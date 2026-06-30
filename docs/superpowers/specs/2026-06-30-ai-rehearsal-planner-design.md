# AI Rehearsal Planner — Design

**Date:** 2026-06-30
**Branch:** `feat/ai-rehearsal-planner`
**Repos:** `tts_bandmate` (Flutter) + `TTS` (Laravel backend)

## Goal

An interactive, AI-powered rehearsal planner. When a band leader opens the
planner, the AI proactively assesses what the band should rehearse based on:

- **Upcoming events** and their requested songs (event setlists).
- **Recently rehearsed songs**, derived from past rehearsals' associated
  bookings and those bookings' event setlists.
- **Personnel & instruments** (roster members and their band roles).
- The band's **song library** (active songs with metadata).

The planner is a **multi-turn chat** (Claude-Code-style): the AI opens with an
assessment and a couple of suggested next steps or an open prompt; the user
replies in natural language or taps a suggested-reply chip; the AI refines and
can produce a structured rehearsal plan.

When nothing is pending on upcoming events, the AI pivots to **suggestions**,
presented in two clearly separated sections:
- **Revisit from your library** — existing, under-rehearsed songs that fit the
  roster.
- **New repertoire ideas** — external songs (not in the library) to learn,
  based on genre and instrumentation.

## Non-goals (v1)

- No new direct rehearsal↔song schema relation (rehearsal songs are derived via
  the existing booking/event-setlist chain).
- No automatic mutation of setlists or rehearsals from the planner; it produces
  plans/suggestions the user reads and acts on manually.
- No image/attachment input (unlike the setlist AI).

## Architecture & data flow

Backend-driven, reusing the existing Laravel AI integration (Anthropic, the
`SetlistAgent`/`SetlistAiService` pattern).

```
Flutter (chat UI)
  │  POST start / POST message
  ▼
Mobile API (RehearsalPlannerController, band-scoped)
  │
  ▼
RehearsalPlannerService
  ├─ gathers context (4 sources, below)
  ├─ persists user + placeholder assistant messages
  └─ dispatches RehearsalPlannerAgent via Laravel AI broadcast()
        │  streams token deltas + final payload
        ▼
   Pusher private channel: private-rehearsal-planner.{session}
        │
        ▼
Flutter subscribes (existing PusherChannelsFlutter wiring) → appends deltas
```

### Context sources (no schema changes)

1. **Upcoming events** for the band (next N), each with date, venue, type, and
   its setlist songs (`Events::setlist` → `setlist_songs` → `songs`).
2. **Past rehearsals** (last N): `Rehearsal → associations (bookings) → those
   bookings' events → event setlists → songs`. These are the songs each past
   rehearsal prepared. Rehearsal `notes` (free text) are also included.
3. **Personnel & instruments**: roster members + their `BandRole` name (the
   role name doubles as the instrument/section, e.g. "Trumpet", "Lead Vocals").
4. **Song library**: active `songs` with title, artist, song_key, genre, bpm,
   rating, energy, lead singer.

### Agent

`App\Ai\Agents\RehearsalPlannerAgent`, mirroring `SetlistAgent`:
- `#[Provider(Lab::Anthropic)]`, model pinned (match the setlist agent's tier).
- Implements `Agent, Conversational` with `withHistory()` so multi-turn
  conversation state is supplied from persisted messages.
- `instructions()`: professional band-rehearsal planner; stays on
  rehearsal/repertoire planning and politely declines off-topic requests.

`RehearsalPlannerService` builds the system context block from the four sources
and orchestrates the streamed turn (mirrors `SetlistAiService` structure).

## Conversation flow

1. **Opening turn (AI-initiated).** Opening a session calls the start endpoint
   with no user message. The service injects the full context block and the
   agent produces an opening assessment:
   - Upcoming events have requested/setlist songs → focus there, naming songs
     not seen in recent rehearsals.
   - Nothing pending → pivot to suggestions ("Revisit from your library" +
     "New repertoire ideas", separated).
   - Ends with a couple of concrete next-step options **or** an open prompt.
2. **User replies** in free text and/or taps a suggested-reply chip.
3. **AI refines** across turns (history-aware) and can emit a **structured
   rehearsal plan** when asked: an ordered list of songs, each with a one-line
   reason. Library songs carry their `song_id`; new-repertoire ideas use
   `song_id: null`.

**Quick-reply chips:** each assistant turn may include up to ~3 model-emitted
suggested replies, rendered as tappable chips. The user can always type freely.

## API contract

Band-scoped, under `/api/mobile/bands/{band}/rehearsal-planner/…`:

- `POST   …/sessions` — start a session. Persists the session and a placeholder
  assistant message (status `streaming`), then runs the opening turn. Returns
  `{ session_id, channel, assistant_message_id }`; the assistant text streams
  over Pusher. (No user message is persisted for the opening turn.)
- `POST   …/sessions/{session}/messages` — body `{ text }`. Persists the user
  turn + a placeholder assistant message. Returns
  `{ user_message, assistant_message_id, channel }`; assistant text streams.
- `GET    …/sessions/{session}` — fetch full message history (resume).

### Assistant message payload (finalized over the stream's `done` event)

```json
{
  "role": "assistant",
  "text": "...markdown...",
  "suggestions": ["Draft a plan for the wedding", "Explore new material"],
  "plan": {
    "title": "Rehearsal plan — Smith Wedding",
    "items": [
      { "song_id": 42, "title": "At Last", "reason": "On the setlist, not rehearsed recently." },
      { "song_id": null, "title": "Signed, Sealed, Delivered", "reason": "New repertoire idea — fits your horn section." }
    ]
  }
}
```

`plan` is optional and present only when the AI produces one. `plan.items`
reference real library song ids where applicable.

## Streaming over Pusher

Laravel AI's `broadcast()` / `StreamableAgentResponse` streams agent output over
a broadcast channel. The app already has full Pusher wiring
(`live_session_provider.dart`: `PusherChannelsFlutter.getInstance()`,
`onAuthorizer` for private channels, `subscribe(channelName, onEvent)`).

- Channel: `private-rehearsal-planner.{session}`, authorized via the existing
  Bearer-token `onAuthorizer`, scoped so only the session's user may subscribe.
- The backend dispatches the agent's streamed turn to that channel; Flutter
  appends token deltas to the placeholder assistant message, then applies the
  final structured payload (`suggestions`, optional `plan`) on the `done` event.

## Persistence

- `rehearsal_planner_sessions` — id, band_id, user_id, title (nullable),
  timestamps.
- `rehearsal_planner_messages` — id, session_id, role (`user`/`assistant`),
  content (text), payload (json: suggestions/plan), status
  (`streaming`/`complete`/`failed`), timestamps.

On each turn: persist user message → persist placeholder assistant message
(status `streaming`) → stream tokens into it → finalize content + payload and
set status `complete`. The `Conversational` agent's history is rebuilt from
these rows.

## Error handling

- Anthropic API key not configured → 503 (matches `SetlistEditorController`).
- Empty song library → planner still works: it skips library suggestions and
  leans on upcoming events + new-repertoire ideas (does **not** 422, unlike the
  setlist generator).
- Stream failure / client disconnect → assistant message marked `failed`;
  Flutter shows a retry affordance on that turn; any partial tokens are kept.
- Off-topic requests → the agent declines per its instructions guardrail.

## Flutter structure

New feature slice `lib/features/rehearsal_planner/` following the project's
`data/` → `providers/` → `screens/` convention:

- `data/rehearsal_planner_repository.dart` — start session, send message, fetch
  history (Dio via the existing `api_client`).
- `data/models/` — `planner_session.dart`, `planner_message.dart`,
  `planner_plan.dart` (hand-written `fromJson`, matching the repo's model style).
- `providers/rehearsal_planner_provider.dart` — `AsyncNotifier` holding the
  message list; manages the Pusher subscription, delta appends, finalize, and
  failed-turn retry.
- `screens/rehearsal_planner_screen.dart` — Cupertino chat UI: message bubbles
  (markdown text), suggestion chips, structured-plan rendering, a composer
  input, and per-turn retry.

Entry point: a "Rehearsal Planner" action surfaced from the rehearsals area
(exact placement decided during planning).

## Backend structure

- `app/Ai/Agents/RehearsalPlannerAgent.php`
- `app/Services/RehearsalPlannerService.php` (context builders + streamed turn)
- `app/Http/Controllers/Api/Mobile/RehearsalPlannerController.php`
- Migrations for the two tables above; `RehearsalPlannerSession` +
  `RehearsalPlannerMessage` models.
- Routes under the existing mobile band group.
- Channel authorization for `private-rehearsal-planner.{session}`.

## Testing

**Backend:**
- Context-builder unit tests (factories): upcoming-events extraction,
  past-rehearsal → booking → setlist song extraction, roster/instrument
  summary, suggestion inputs.
- Controller + channel-authorization tests.
- A fake/stubbed agent so tests make no live API calls.

**Flutter:**
- Provider tests with a fake repository + fake Pusher: opening turn, append
  deltas, finalize payload, failed-turn retry.
- Widget tests: chat screen, suggestion chips, structured-plan rendering.

## Open items deferred to planning

- Exact `N` for upcoming events / past rehearsals windows.
- Model tier for the agent (match setlist agent unless cost dictates otherwise).
- Entry-point placement in the rehearsals UI.
