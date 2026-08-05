# Lodging Domain — Design

**Date:** 2026-08-04
**Repos:** TTS (Laravel backend + web) and tts_bandmate (Flutter mobile)
**Status:** Approved

## Problem

Lodging today is a generic `{type, title, data}` field list stored in
`band_events.additional_data.lodging`, edited as dumb form inputs on web
(`LodgingSection.vue`) and shown read-only on mobile. It cannot represent a
real hotel stay: multiple rooms, its own check-in/check-out times, a mappable
location, or photos of instructions.

## Goal

Promote lodging to a first-class, band-scoped domain, independent of bookings
and events but optionally linkable to either, with full mobile/web parity.

Supported scenario: several rooms in one hotel; check-in/check-out
dates/times separate from any booking/event; tappable navigation to the
location via the existing maps functionality; instructions/notes with
attachable images. Room-to-person assignment is explicitly out of scope (the
schema leaves a hook for it).

## Decisions (from brainstorming)

- **Independent + optional link:** top-level band entity with its own CRUD;
  nullable `booking_id` and `event_id` links surface it in context.
- **Structured room rows:** each room is a row (label, confirmation number,
  note) with a stable id — future room-assignment hook.
- **Legacy data:** old event-editor lodging UI is removed; existing
  `additional_data.lodging` JSON stays in the DB, unrendered. No migration.
- **Navigation:** mobile More/Operations tab entry + web nav item; linked
  stays also shown on booking/event detail in both apps.
- **Permissions:** members read, band write permission edits; subs get
  read-only access to lodgings linked to events they play.
- **Architecture:** relational tables + dedicated `lodging_attachments`
  (EventAttachment pattern), not the band media library — hotel photos stay
  private to the lodging record.

## Backend data model (TTS)

```
lodgings
  id, band_id FK, name,
  address (nullable), latitude (nullable), longitude (nullable),
  check_in_at (datetime), check_out_at (datetime),
  notes (text, nullable),
  booking_id (nullable FK -> bookings),
  event_id   (nullable FK -> events),
  timestamps, soft deletes

lodging_rooms
  id, lodging_id FK (cascade), label,
  confirmation_number (nullable), notes (nullable), sort_order

lodging_attachments        -- cloned from event_attachments
  id, lodging_id FK (cascade), filename, stored_filename,
  mime_type, file_size, disk, timestamps
```

`Lodging` model uses `BroadcastsBandChanges` (thin realtime invalidation) and
`LogsActivity`, matching `Events`. Attachments served via the existing
`/images/` proxy route (`ImageController`).

Datetime storage follows the existing events convention (band-local
semantics, no new timezone handling).

## API

### Web (Inertia)

`LodgingController`: index / create / store / show / edit / update / destroy,
plus attachment upload/delete endpoints. Band-scoped like existing
controllers. Web routes in a new `routes/lodging.php` (matching the
per-domain layout of `booking.php`, `events.php`, etc.); mobile routes in
the existing `/api/mobile` group in `routes/api.php`.

### Mobile (`/api/mobile`)

New ability pair `read:lodging` / `write:lodging` following the
`mobile.band:read:events` middleware pattern:

- `GET    /lodgings` — list, upcoming-first
- `GET    /lodgings/{id}` — detail (rooms + attachments included)
- `POST   /lodgings`
- `PATCH  /lodgings/{id}`
- `DELETE /lodgings/{id}`
- `POST   /lodgings/{id}/attachments` — multipart upload
- `DELETE /lodgings/{id}/attachments/{attachmentId}`

Rooms travel nested in the lodging payload. Update semantics: rows with `id`
update, rows without `id` insert, ids missing from the payload delete.

Booking detail and event detail mobile responses gain a `lodgings` summary
array (id, name, check_in_at, check_out_at, address) so linked stays surface
in context.

## Permissions & sub visibility

- Full band members: read all band lodgings.
- Band write permission (same gate as events/bookings) required for
  create/edit/delete and attachment mutations.
- Subs: read-only visibility of lodgings whose `event_id` is an event they
  are assigned to, or whose `booking_id` owns such an event — reusing the
  event-membership query that powers sub event visibility. Unlinked lodgings
  are invisible to subs.
- All sub queries are explicitly scoped by the `X-Band-ID` band server-side;
  do not rely on token abilities alone (known band-agnostic-abilities leak).

## Web UI (Vue/Inertia)

- "Lodging" link in the band nav.
- **Index:** card list, upcoming stays first; name, dates, room count,
  linked booking/event chip.
- **Create/Edit:** name, address (existing autocomplete component),
  check-in/check-out datetime pickers, notes, room rows (add/remove),
  image attachments (upload/preview/delete), optional booking and event
  pickers.
- **Booking/Event pages:** lodging card listing linked stays, linking to the
  lodging page.
- Remove `LodgingSection.vue` from the event editor.

## Mobile UI (Flutter, Cupertino)

New `features/lodging/` slice (`data/` → `providers/` → `screens/`):

- Entry on the More/Operations tab beside Personnel
  (`operations_screen.dart`).
- **List:** upcoming stays first, past stays collapsed below.
- **Detail:** name; tappable address row launching maps using a shared
  maps-launch helper — extracted from the duplicated code in
  `event_edit_screen.dart` and `event_sub_form_card.dart` as part of this
  work; check-in/check-out with day-of-week formatting; rooms list; notes;
  attachment thumbnail grid (tap to view); linked booking/event navigation.
- **Edit** (write permission only): mirrors web fields; reuses
  `AddressAutocompleteField`; image picking via the existing image-picker
  flow.
- Event and booking detail screens show a lodging card when linked stays
  exist.
- Dark-mode text via `context.secondaryText`; layouts verified at 320pt
  width.
- A 403 on lodging endpoints renders as "feature hidden", not an error
  banner (stale tokens lack the new abilities until re-login/refresh).

## Testing

- **Backend feature tests:** CRUD, band scoping, sub visibility (linked vs
  unlinked, cross-band), attachment upload/delete, ability enforcement.
  Run files serially where the known unique-constraint flakes apply.
- **Mobile unit tests:** repository/model parsing and provider logic with
  fakes, mirroring existing test style. Date logic relative to `now()` — no
  hardcoded time-bomb dates.

## Rollout

1. Backend PR to TTS, base `staging` (auto-deploys on merge).
2. Mobile PR to tts_bandmate, base `main`. The `feat:` commit triggers
   release-please's 1.23.0 release PR automatically — no manual version
   bump.
3. On-device verification against local backend before store rollout;
   re-login locally to pick up the new token abilities.
