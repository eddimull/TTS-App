---
name: Dashboard Live Now card
description: How the "Live Now" current-event banner is implemented on the dashboard — computed getter pattern, pulsing dot widget, and placement above the calendar.
type: project
---

The dashboard surfaces a "Live Now" banner when an event is currently in progress.

**Architecture:**
- `currentEvent` is a computed getter on `DashboardState` (in `dashboard_provider.dart`) — no new provider or API call. It iterates `events` looking for one whose date is today and whose `[startTime, startTime + 4h]` window contains `DateTime.now()`. Events with no start time match the entire calendar day.
- `_DashboardContent` receives `currentEvent` as a nullable parameter and conditionally renders `LiveNowCard` as the first item in its `SliverChildListDelegate`, above the `TableCalendar`.
- Navigation from the card reuses the same `_navigateToEvent` logic already present in `_EventsList`.

**Widget — `lib/features/dashboard/widgets/live_now_card.dart`:**
- `LiveNowCard` is a `StatefulWidget` (needs `AnimationController` for the pulsing dot).
- Pulsing red dot: `AnimationController` repeating 0.4→1.0 opacity, `CustomPaint` with `_DotPainter` drawing an outer ripple ring + solid inner dot.
- Card uses a tinted red background (`systemRed` at 7% / 18% for light/dark) with a matching border — intentionally understated so it doesn't overpower the rest of the screen.
- Header row: pulsing dot + "LIVE NOW" label (caps, letter-spaced) + chevron right.
- Body row: gig icon (reuses `gigIconPath` asset or a mic-in-circle for rehearsals) + title + date/time/venue subtitle joined by `·` separators.
- `Semantics(button: true, label: 'Live now: <title>. Tap to open event.')` wraps the whole card.

**Why:** No separate API endpoint exists for "current event" — the dashboard endpoint already returns all relevant events, so a pure computed approach is zero-cost and always in sync with the pulled data.

**How to apply:** If a feature needs to derive a "highlighted" or "active" event from an existing list, add a computed getter to the relevant state class rather than introducing a new provider or fetch.
