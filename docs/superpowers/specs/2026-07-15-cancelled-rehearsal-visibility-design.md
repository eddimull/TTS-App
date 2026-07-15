# Cancelled Rehearsal Visibility — Design

**Date:** 2026-07-15
**Repos:** TTS-App (Flutter, branch `feat/cancelled-rehearsal-visibility`, PR → `main`) and TTS (Laravel, PR → `staging`)

## Problem

Cancelling a rehearsal (shipped in App#88 / TTS#509) is only visible inside the
Rehearsals tab and detail screen. Everywhere else the rehearsal looks alive:

- The shared surfaces — events list cards, dashboard cards, and calendar day
  markers — render rehearsals via `EventSummary`, which carries no cancelled
  flag, so no styling is possible.
- The Google Calendar event (created via the rehearsal's backing `Events` row)
  is never updated on cancel.
- The ICS calendar feed keeps emitting the rehearsal as a normal VEVENT.

## Decisions (user-confirmed)

1. All shared app surfaces get the cancelled treatment (cards + calendar markers).
2. Google Calendar keeps the event but marks it: red color + "Cancelled: " title
   prefix. Restore reverts it.
3. The ICS feed also marks cancelled rehearsals (`STATUS:CANCELLED` + prefix).
4. Backend wiring is cancellation-aware representation (the calendar summary /
   color / status methods read `is_cancelled`), not one-off patching in the
   cancel job — so bulk re-syncs (`SyncCalendar`) stay correct.

## Design

### 1. Mobile API (TTS)

The mobile events index (`app/Http/Controllers/Api/Mobile/EventsController.php`)
adds `is_cancelled` (boolean) to each rehearsal-sourced entry, read from the
backing `Rehearsal` model. Booking/plain-event entries send `false`. No schema
change: `rehearsals.is_cancelled` already exists.

### 2. App shared surfaces (Flutter)

- `EventSummary` (`lib/features/events/data/models/event_summary.dart`) gains
  `final bool isCancelled`, parsed as `(json['is_cancelled'] as bool?) ?? false`.
- `EventCard` (`lib/features/dashboard/widgets/event_card.dart`), when
  `isCancelled` is true: red `CupertinoIcons.xmark_circle` replaces the type
  icon, title gets `TextDecoration.lineThrough` + `context.secondaryText`, a
  small red "Cancelled" label appears, and the rehearsal blue tint becomes a
  neutral gray tint. Matches the Rehearsals-tab treatment
  (`rehearsals_screen.dart:232-264`).
- Calendar day marker
  (`lib/features/dashboard/widgets/calendar_event_marker.dart`): extend the
  existing booking-cancelled ring treatment (red ring, faded) to
  rehearsal-sourced events with `isCancelled`.
- Navigation and the live-session badge are unchanged; cancelled rehearsals
  remain tappable.

### 3. Google Calendar sync (TTS)

- `Rehearsal::getGoogleCalendarSummary()` and the rehearsal branch of
  `Events::getGoogleCalendarSummary()` prefix `Cancelled: ` when
  `is_cancelled`.
- The corresponding color methods return `'11'` (tomato/red) instead of `'5'`
  (yellow) when cancelled.
- `ProcessRehearsalCancelled` (fires on both cancel and restore) additionally
  dispatches the existing event-updated sync (`ProcessEventUpdated`) for the
  rehearsal's backing `Events` row so the Google event re-renders immediately.
- Restore reverts automatically — the representation methods just read the flag.

### 4. ICS feed (TTS)

`CalendarFeedController::buildEvent()` checks whether the event's `eventable`
is a cancelled `Rehearsal`; if so, prefix the VEVENT name with `Cancelled: `
and set `STATUS:CANCELLED`. Other events untouched.

### 5. Error handling

- Flutter parse uses null-safe coalescing; a backend that doesn't yet send the
  field renders exactly as today (deploy backend first regardless).
- Calendar sync failures follow the existing job retry/log behavior; no new
  failure modes introduced.

### 6. Testing

- Flutter: `EventSummary` parsing test (present/absent/null field); widget test
  asserting cancelled `EventCard` styling (icon, strikethrough, label); marker
  ring test for cancelled rehearsal.
- Laravel: events-index feature test asserting `is_cancelled`; unit coverage
  that a cancelled rehearsal's Google event data has red color + prefixed
  summary; `CalendarFeedTest` case asserting `STATUS:CANCELLED` (run this file
  sequentially — known parallel flake). No hardcoded now-relative dates.

### Rollout

Backend (TTS → staging, auto-deploys) first; app PR after. The app tolerates a
missing field, and the backend field is additive, so ordering is safe either way.
