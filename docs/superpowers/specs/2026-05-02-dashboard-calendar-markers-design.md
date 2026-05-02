# Dashboard Calendar — Band-Aware Markers + Floating Filter

**Date:** 2026-05-02
**Status:** Draft for review

## Problem

The dashboard calendar (`lib/features/dashboard/screens/dashboard_screen.dart`) aggregates events from every band the user belongs to, but renders each day's events as an identical blue dot. The user can't tell at a glance which band is booked on a given day, what kind of event it is (rehearsal vs. paid gig vs. other), or whether a booking is confirmed. There is also no way to narrow the calendar down to a subset of bands or event types.

## Goals

1. A user looking at the calendar can identify, *without tapping*, which band is booked on each day.
2. A user can distinguish performances from rehearsals from other band events at the same glance, and can see whether a booking is still pending.
3. A user can filter the calendar to a chosen subset of bands and event types.
4. Existing call sites and the rest of the dashboard layout continue to work unchanged.

## Non-goals

- Persisting filter state across app restarts (intentionally session-scoped).
- Tap-to-filter from a marker.
- Adding new event-type categories beyond the existing three sources (`booking`, `rehearsal`, `band_event`).
- Backend changes. All required data already flows through `EventSummary.band` and `BandSummary.logoUrl`.

## Solution overview

Three coordinated changes:

1. **Marker rendering** — replace the global blue-dot `markerDecoration` in `_CalendarSection` with a custom `CalendarBuilders.markerBuilder` that draws small band-avatar circles (logo or initial fallback) with a colored ring. The ring encodes event type and booking confirmation.
2. **Floating filter button + sheet** — add a persistent filter affordance bottom-right of the dashboard. Tapping opens a Cupertino modal popup with band chips and event-type switches; selections live-update the calendar. Filter state is held in a `Notifier` provider and resets on app restart.
3. **Shared `BandAvatar` widget** — promote the private `_Avatar` from `band_identity_chip.dart` to a public `BandAvatar` in `lib/shared/widgets/band_avatar.dart`, switch its image loading to `cached_network_image`, and use it everywhere a band logo is rendered.

## Marker rendering

### Per-event marker

A single marker is an 18px circular `BandAvatar` with a 2px ring drawn around it.

- **Avatar fill:** band's `logoUrl` via `cached_network_image`. If null, fall back to a colored circle with the band's initial (existing behavior of `_Avatar`).
- **Ring:** 2px stroke, color and style determined by the table below.

### Multi-event days

| Events on day | Layout |
|---|---|
| 1 | single avatar centered in the marker slot |
| 2 | two avatars side-by-side with 2px overlap, ordered by event time (earliest first, nulls last) |
| 3+ | first avatar + a "+N" pill (e.g. "+2") in `systemGrey` |

`TableCalendar`'s `markerBuilder` receives the list of events for a given day; the new `CalendarDayMarkers` widget composes 1, 2, or "+N" from that list.

### Cell sizing

The default `TableCalendar` `rowHeight` (~52) is tight for 18px markers. Bump to ~56 to keep markers from crowding day numbers. Pure visual tuning, no semantic risk.

### Implementation files

`lib/features/dashboard/widgets/calendar_event_marker.dart`:

- `CalendarEventMarker` — a single avatar + ring for one `EventSummary`.
- `CalendarDayMarkers` — composes 1 / 2 / "+N" from a `List<EventSummary>`.
- `DashedCircleBorderPainter` — a `CustomPainter` that strokes a circle with a dash pattern (4px dash / 3px gap), used for pending bookings.

## Ring color + status mapping

| Event source | Status | Ring color | Ring style | Avatar opacity |
|---|---|---|---|---|
| `booking` | confirmed | `systemGreen` | solid 2px | full |
| `booking` | pending / unconfirmed / null | `systemGreen` | dashed 2px | full |
| `booking` | cancelled | `systemRed` | solid 2px | 40% |
| `rehearsal` | any | `systemBlue` | solid 2px | full |
| `band_event` | any | `systemGrey` | solid 2px | full |

All colors use `Cupertino*.resolveFrom(context)` so they adapt to dark mode.

### Booking status normalization

`event.status` is a free-form string from the backend. A new helper:

`lib/shared/utils/booking_confirmation.dart`

```dart
enum BookingConfirmation { confirmed, pending, cancelled }

BookingConfirmation bookingConfirmationFromStatus(String? status) {
  final s = (status ?? '').toLowerCase();
  if (s.contains('cancel')) return BookingConfirmation.cancelled;
  if (s == 'confirmed' || s == 'booked' || s == 'accepted') {
    return BookingConfirmation.confirmed;
  }
  return BookingConfirmation.pending;
}
```

The exact string set will be verified against the backend during implementation. Worst case for an unrecognised string is "confirmed booking renders as dashed (pending)" — the visual is still meaningful.

### Accessibility

Color is the only visual signal for type/status, so each marker is wrapped in `Semantics(label: '<bandName> <eventType>, <status>')`. Days with multiple events combine their labels.

## Filter UX

### Floating filter button

`lib/features/dashboard/widgets/calendar_filter_button.dart`.

- Position: `Stack` + `Positioned` overlay inside the dashboard scaffold, anchored bottom-right at 16px from the right edge, 16px above the `CupertinoTabBar` (49pt + `MediaQuery.padding.bottom`).
- Size: 48×48 circular with a soft shadow.
- Icon: `CupertinoIcons.line_horizontal_3_decrease`.
- **Inactive:** `tertiarySystemBackground` fill, `systemBlue` icon.
- **Active** (any filter applied): `systemBlue` fill, white icon.
- **Badge:** small red 16px circle at top-right showing `hiddenBandIds.length + hiddenEventTypes.length`. Cap display at "9+". Hidden when count is 0.
- `Semantics` wrapper: label "Filter calendar"; hint reflects the active count.

The button does not conflict with the existing "+" in `CupertinoSliverNavigationBar` — the icon and position are clearly distinct from "create."

### Filter sheet

`lib/features/dashboard/widgets/calendar_filter_sheet.dart`. Opened via `showCupertinoModalPopup`, matching the existing `CreateBookingSheet` pattern.

Top-down structure:

1. **Drag handle** — 36×4 rounded pill, `systemGrey4`.
2. **Header** — "Filter" (17pt semibold, centered). On the right: a "Clear All" `CupertinoButton` (destructive red), visible only when at least one filter is active.
3. **Bands section** — "BANDS" label (13pt grey uppercase) and a horizontal scrollable row of band chips. Each chip is ~64px wide: a 40px `BandAvatar` plus the band name (12pt, 1 line ellipsis) below. See "Available bands for the filter sheet" below for the visible/hidden chip states.
4. **Event Types section** — "EVENT TYPES" label and three `CupertinoSwitch` rows: "Performances" (`booking`), "Rehearsals" (`rehearsal`), "Other Events" (`band_event`). All default to on.
5. **Bottom safe-area padding.**

### Interaction

- Live update — every tap immediately mutates the provider and updates the calendar behind the sheet. No "Apply" button.
- `HapticFeedback.selectionClick()` on each toggle.
- Sheet dismisses on swipe-down or tap-outside; filter state persists until app restart.

### Empty-state branch

The events list below the calendar already shows `EmptyStateView` when `_filteredEvents` is empty. Add a filter-aware variant: when `filter.isActive` and the list would have been non-empty without the filter, swap the message to "No events match your filters" and add an inline `CupertinoButton.filled` "Clear filters" that calls `clear()` on the provider.

## Data flow & state

### New provider

`lib/features/dashboard/providers/calendar_filter_provider.dart`:

```dart
class CalendarFilterState {
  const CalendarFilterState({
    this.hiddenBandIds = const {},
    this.hiddenEventTypes = const {},
  });

  final Set<int> hiddenBandIds;
  final Set<String> hiddenEventTypes; // 'booking', 'rehearsal', 'band_event'

  bool get isActive => hiddenBandIds.isNotEmpty || hiddenEventTypes.isNotEmpty;
  int get activeCount => hiddenBandIds.length + hiddenEventTypes.length;

  bool isEventVisible(EventSummary event) {
    if (event.band != null && hiddenBandIds.contains(event.band!.id)) {
      return false;
    }
    if (hiddenEventTypes.contains(event.eventSource)) return false;
    return true;
  }

  CalendarFilterState copyWith({
    Set<int>? hiddenBandIds,
    Set<String>? hiddenEventTypes,
  }) => CalendarFilterState(
        hiddenBandIds: hiddenBandIds ?? this.hiddenBandIds,
        hiddenEventTypes: hiddenEventTypes ?? this.hiddenEventTypes,
      );
}

class CalendarFilterNotifier extends Notifier<CalendarFilterState> {
  @override
  CalendarFilterState build() => const CalendarFilterState();

  void toggleBand(int bandId) { /* add/remove from hiddenBandIds */ }
  void toggleEventType(String source) { /* add/remove from hiddenEventTypes */ }
  void clear() => state = const CalendarFilterState();
}

final calendarFilterProvider =
    NotifierProvider<CalendarFilterNotifier, CalendarFilterState>(
  CalendarFilterNotifier.new,
);
```

Synchronous in-memory `Notifier`. State resets on app restart — no persistence.

### Available bands for the filter sheet

Derived from `authProvider`'s `AuthAuthenticated.bands`. The sheet renders the full list. Two visual states for the band chips:

- **Visible on calendar** (i.e. *not* in `hiddenBandIds`) — full opacity with a 2px `systemBlue` ring around the avatar.
- **Hidden** (in `hiddenBandIds`) — 40% opacity, no ring.

Bands with zero events in the loaded event window are still rendered with these same two states; tapping such a chip is technically a no-op for the current window but the user sees a consistent toggle. No third "empty" state.

### Wiring into the dashboard

`_DashboardContent` watches `calendarFilterProvider` and applies `state.isEventVisible` on top of the existing month/day filtering:

```dart
final visibleEvents = widget.events.where(filter.isEventVisible).toList();
```

`visibleEvents` then drives:

- The day-keyed event map for marker rendering.
- `_filteredEvents` (the events list below).

### `_getEventsForDay` change

Currently returns `[Object()]` as a presence sentinel. Updated to return the actual events for that day so the marker builder can render avatars + rings:

```dart
List<EventSummary> _getEventsForDay(DateTime day) =>
    _eventsByDay[_normalise(day)] ?? const [];
```

`_eventsByDay` is a `Map<DateTime, List<EventSummary>>` computed once per build from `visibleEvents`. `TableCalendar`'s generic type changes from `<Object>` to `<EventSummary>`.

### Marker order on multi-event days

Sort by `event.time` (earliest first, nulls last). Stable on ties.

## Shared `BandAvatar` widget

The private `_Avatar` in `lib/shared/widgets/band_identity_chip.dart` is exactly the avatar the marker needs. Promote it to public, switch to cached image loading, and reuse:

- **New file** `lib/shared/widgets/band_avatar.dart` — a plain `StatelessWidget` `BandAvatar` with two named constructors:
  - `BandAvatar.forBand({required BandSummary band, double size = 18})` — renders the band's `logoUrl` or initial-letter fallback.
  - `BandAvatar.forUser({required String? imageUrl, required String name, double size = 18})` — renders a user's avatar (used for personal-band rows).

  Uses `CachedNetworkImage` from the existing `cached_network_image: ^3.3.1` dependency for image loading. The auth lookup for the personal-band case stays in `BandIdentityChip` (which is already a `ConsumerWidget`); `BandAvatar` itself does not depend on Riverpod.
- **Modified** `lib/shared/widgets/band_identity_chip.dart` — uses `BandAvatar.forBand` / `BandAvatar.forUser`, drops the private `_Avatar`. No behavior change at existing call sites.
- **Used by** the new marker (`CalendarEventMarker`), the filter chips (`CalendarFilterSheet`), and any future place a band avatar is needed.

## File-by-file change list

### New files

- `lib/features/dashboard/providers/calendar_filter_provider.dart`
- `lib/features/dashboard/widgets/calendar_event_marker.dart`
- `lib/features/dashboard/widgets/calendar_filter_button.dart`
- `lib/features/dashboard/widgets/calendar_filter_sheet.dart`
- `lib/shared/utils/booking_confirmation.dart`
- `lib/shared/widgets/band_avatar.dart`

### Modified files

- `lib/features/dashboard/screens/dashboard_screen.dart` — wraps the scaffold body in `Stack` with the floating filter button overlay; `_DashboardContent` watches `calendarFilterProvider` and derives `visibleEvents`; `_CalendarSection` accepts `Map<DateTime, List<EventSummary>>`; `TableCalendar` becomes `<EventSummary>` with a custom `markerBuilder`; `markerDecoration` removed from `CalendarStyle`; the empty-state branch gains a filter-aware variant with an inline "Clear filters" button.
- `lib/shared/widgets/band_identity_chip.dart` — uses `BandAvatar`, drops the private `_Avatar`.

(`pubspec.yaml` is unchanged — `cached_network_image: ^3.3.1` is already a direct dependency.)

## Testing

- **Unit:** `CalendarFilterState.isEventVisible` — table-driven across hidden-band and hidden-event-type combinations against a sample `EventSummary`.
- **Unit:** `bookingConfirmationFromStatus` — covers `confirmed`, `booked`, `accepted`, variants of `cancel*`, `pending`, unknown strings, and null.
- **Widget:** `CalendarDayMarkers` — asserts that 1-, 2-, and 3-event days render the correct number of avatars and the "+N" pill at the right threshold.
- **Widget:** `CalendarFilterSheet` — toggling a band chip mutates `calendarFilterProvider`; "Clear All" only renders when filters are active; tapping "Clear All" empties the provider.
- **Widget:** dashboard integration — given a fixed event list, hiding a band hides those days' markers and rows; the filter-aware empty state appears when filters hide everything.

## Risks and known limits

1. **Logo URLs may be null** for many bands today (`logoUrl` is nullable). The colored-initial fallback handles this, but the visual density depends on logos becoming common over time. Out of scope to backfill.
2. **Status string normalization** is a guess until the backend strings are confirmed. Worst case: a confirmed booking renders dashed. Will be verified during implementation.
3. **Calendar row height** may need to bump from ~52 to ~56 to fit 18px markers. Pure visual tuning.
4. **Web/desktop FAB placement** — the dashboard isn't width-clamped today, so the FAB pins to the screen edge. If the dashboard later gains a centered max-width column, the FAB position should follow the content column. Tracked as a follow-up if it looks wrong on desktop.
5. **`_getEventsForDay` signature change** propagates through `_CalendarSection`. Minor refactor, no external API surface.
6. **Performance** — switching to `cached_network_image` mitigates the per-rebuild network load that would otherwise occur with many marker avatars in a heavy month.
