# Event-Day "Leave By" Notifications — Design

**Date:** 2026-06-13
**Status:** Approved for planning
**Scope of this spec:** Flutter app (`tts_bandmate`). The Laravel backend work is documented here as an interface contract and will get its own spec in the backend repo.

## Summary

Notify a band member on the day of an event they're rostered for, with up to two notifications:

1. An **8h-before reminder** ("you have an event today"), enriched with venue and "leave by" travel times when possible.
2. A **departure reminder** ("leave in 15 minutes") timed off live travel time to make the first timeline item.

The headline behavior — "leave by [time] based on where you are right now" — requires the user's live location, which only the device knows. To guarantee delivery even when the app is closed (the safety-net case: someone forgets a gig), the **server** sends the notifications via true push (FCM/APNs) using data it owns, and the **device enriches** them with live location when reachable. When the device is unreachable, notifications degrade gracefully to plain time-based text.

## Goals

- A rostered user is reliably warned on event day even if they never open the app (true push safety net).
- When the app is reachable, the reminder reflects live travel time from the user's current location.
- Suppress the departure reminder if the user has already left.
- Never more than two notifications per event per day.

## Non-Goals

- Notifications for events the user is not actively rostered for.
- Geofencing or continuous background location tracking.
- Activity/motion recognition.
- Backend implementation (documented as a contract only).

## Architecture

**Hybrid: server-guaranteed push, device-enriched with live location.**

Three cooperating pieces:

1. **Backend (Laravel — separate spec).** Owns the schedule and guarantees delivery. For each event today the user is rostered for, schedules two pushes via FCM/APNs: an 8h-before reminder and a departure reminder. Computes timing from event data it already has (timeline times, venue). Sends time-based text by default; includes "leave by" values only when it has fresh device location.

2. **Flutter app.**
   - *Token + location plumbing:* registers its FCM/APNs device token with the backend; reports the device's last-known location so the backend can enrich.
   - *Live enrichment:* when open/reachable, computes real travel time from current location to the venue (Google Directions API) and either upgrades the notification text or suppresses it ("already left" proximity check), scheduling the precise local departure notification.

3. **Pusher (existing).** Unchanged role. If an event's timeline changes while the app is open, triggers a refresh so backend reschedule and app state stay in sync.

**The boundary:** the safety net (you-have-a-gig-today) is always delivered by the server using data it owns. The location-aware "leave by" is a best-effort upgrade that happens only when the device is reachable. Absent location, notifications degrade to plain time-based text.

## Notification Content & Rules

Two notifications max, on the day of the event.

### ① 8h-before reminder (server-scheduled ~8h before the first timeline item)

| Situation | Body |
|---|---|
| Venue + multiple timeline items + **location reachable** | `[Event] · [Venue] · Leave by [t1] for Load In 2:00pm, Leave by [t2] for Show 7:00pm` |
| Venue + multiple items + **no location** | `[Event] · [Venue] · Load In 2:00pm, Show 7:00pm` |
| Single timeline item (or only one usable time) | `[Event] · [Venue] · Load In 2:00pm` |
| No usable venue / can't geocode | `[Event] today · Load In 2:00pm, Show 7:00pm` (times if present, else just `[Event] today`) |

- **First item** = timeline entry with the earliest `time`.
- **Show time** = the event's `startTime` field (not parsed from a timeline title).
- Both "leave by" values require live location; absent it, they are dropped while the rest of the structure stays.

### ② Departure reminder ("leave in 15 minutes")

- Fires 15 min before the user must depart to make the **first timeline item** (load-in), based on live travel time.
- **Location reachable:** `Leave in 15 min for [Event] — Load In 2:00pm` (timed precisely off the travel estimate).
- **Not reachable (fallback):** plain time-based reminder at a sensible default offset before the first item: `[Event] — Load In 2:00pm today`.
- **"Already left" suppression:** when this reminder is about to fire, a single live-location read checks whether the user is already substantially closer to the venue than their origin (or within a proximity radius). If so, suppress it — no notification.

### Scope & cap

- Only events where the user is an **active roster member**.
- Hard cap: never more than these two notifications per event per day, enforced on both device and server.

## Flutter Components

New feature slice: `lib/features/notifications/` (mirrors existing `data/` → `providers/` → `services/`).

### New packages

- `firebase_messaging` + `firebase_core` — receive push, manage device token.
- `flutter_local_notifications` — render/upgrade notifications and schedule the precise local departure reminder.
- `geolocator` — current location + distance math (none today).

### Components

1. **`PushTokenService`** — on login/app-start, fetches the FCM/APNs token and registers it with the backend (`POST /api/mobile/devices`). Re-registers on token refresh. Deregisters on logout.

2. **`LocationReporter`** — when the app is foregrounded on an event day, does a single `geolocator` read and reports it to the backend (`POST /api/mobile/location`) so the server can enrich the 8h push. Permission-gated; silent no-op if denied.

3. **`NotificationHandler`** — receives incoming pushes (`firebase_messaging` foreground/background handlers). For a data push carrying event context it:
   - reads current location,
   - calls the Google Directions API (REST, reusing `AppConfig.googlePlacesApiKey`) for travel time to the venue,
   - runs the "already left" proximity check → suppress, or
   - schedules/updates the precise local departure notification via `flutter_local_notifications`.

4. **Directions client / `travelTimeProvider`** — thin REST wrapper around `maps.googleapis.com/maps/api/directions/json` returning duration. Mirrors the existing Geocoding REST pattern in `lib/features/bookings/widgets/venue_picker.dart`. Lives in the feature's `data/`.

### Data flow (event day)

```
App opens → PushTokenService registers token (once)
          → LocationReporter sends current location

8h out:   Backend sends 8h push (enriched if it has fresh location, else time-based)
          → device shows it; if app reachable, NotificationHandler upgrades text

Departure: Backend sends a DATA push ("compute departure for event X")
          → device: location read → Directions travel time
            → already left? suppress
            → else schedule LOCAL "leave in 15 min" notification at the right moment
          (if device unreachable: backend's own time-based push fires as fallback)
```

### Dedup

Notifications keyed by `eventKey + type`. A local upgrade replaces the same-keyed server notification rather than stacking. Hard cap of 2/event/day enforced on both ends.

### Initialization

- `firebase_core` init added to `main.dart` before `runApp`.
- Background message handler registered as a top-level function (FCM requirement).
- Location permission requested contextually (first event-day app open), not at cold start.

## Backend Interface (contract; implemented in separate Laravel spec)

### Device registration

```
POST /api/mobile/devices
  body: { token, platform: "ios" | "android" }
  → 200. Idempotent (upsert by token). Associates token with authed user.

DELETE /api/mobile/devices/{token}   // on logout
```

### Location reporting

```
POST /api/mobile/location
  body: { lat, lng, recorded_at }
  → 200. Backend stores last-known location for enrichment (staleness/TTL honored).
```

### Push payloads (server → device)

**Hard contract (Phase 1, as implemented):** messages are **data-only** — no `notification` block. FCM data maps are flat string→string, so timeline fields are flattened (no nested objects) and use these exact **camelCase** keys. The device parses them in `PushPayload.fromData` and renders the body itself; a `notification` block would cause the OS to render a duplicate while the app is foregrounded, so the backend must not send one.

8h reminder (data-only):

```
data: {
  type: "event_reminder_8h",   // required
  eventKey: "<string>",         // required
  title: "<event title>",       // shown as the notification title
  venueAddress?: "<string>",
  firstItemTitle?: "<string>",  // e.g. "Load In"
  firstItemTime?: "<ISO-8601 or HH:mm>",
  showTime?: "<ISO-8601 or HH:mm>"
  // Phase 2 will add: leaveByFirst?, leaveByShow?
}
```

Departure trigger (data-only, Phase 2 — modeled now, inert in Phase 1):

```
data: {
  type: "event_departure",
  eventKey: "<string>",
  title: "<event title>",
  venueAddress: "<string>",
  firstItemTitle: "<string>",
  firstItemTime: "<ISO-8601 or HH:mm>"
}
```

Unknown `type` values parse to `PushType.unknown` and are ignored safely.

The backend also schedules a time-based fallback notification for the same event at the default offset. If the device-computed local notification is scheduled, the app cancels/replaces the fallback via the dedup key (`eventKey + type`). If the device never checks in, the server fallback fires.

### Backend responsibilities (documented, not built here)

- Select today's events per user roster (active members only).
- Compute the 8h and departure schedule times from the timeline.
- Enrich `leaveBy*` fields only if it has fresh device location (else omit).
- Enforce max 2 notifications/event/day server-side.
- Reschedule on timeline change (Pusher already broadcasts these).

## Testing

- **Unit (pure functions, `ProviderContainer` + fakes per existing pattern):**
  - timeline parsing — earliest-time entry as first item, `startTime` as show time;
  - notification-body builder across the full content matrix;
  - "already left" proximity decision;
  - dedup keying.
- **Fakes:** `FakeGeolocator`, `FakeDirectionsClient`, `FakePushToken` — no live network/location in tests.
- **Manual:** push delivery + local scheduling verified on real iOS/Android devices (FCM/APNs cannot be unit-tested end-to-end).

## Open Items / Dependencies

- **Push credentials are greenfield.** Requires creating a Firebase project, adding an iOS APNs key, wiring `firebase_messaging`, and device-token registration. The implementation plan must include a setup/verification step.
- **Default departure offset** for the time-based fallback (when no location) — pick a sensible constant (e.g. a fixed lead time before the first item); finalize during planning.
- **Proximity radius / "already left" threshold** — tune during implementation against real device readings.
- **Directions API enablement** — confirm the existing Google API key has the Directions API enabled (currently only Places/Geocoding are used).
