# Lodging Adjustments — Design

**Date:** 2026-08-05
**Repos:** TTS (Laravel + Vue) and tts_bandmate (Flutter)
**Status:** Approved
**Builds on:** `2026-08-04-lodging-domain-design.md` (shipped: TTS #563, App #134)

## Problems

1. Linking a stay to a booking/event presents a flat list of ~100 future
   gigs (events from 3 months back, bookings newest-created-first) with no
   search and no awareness that the stay's dates almost always sit on or
   near the target gig.
2. Lodging is invisible on the mobile dashboard calendar; the only in-app
   discovery is a card buried 7th on the event detail screen.
3. The web advance page still renders a legacy artifact ("There will be
   lodging." off the old `event.lodging` scalar) and shows nothing from
   the new lodging domain. The web dashboard shows nothing either.
4. The mobile event detail screen orders sections reference-first
   (Notes/Attachments before Attire/Lodging), forcing scrolling for
   day-of-show information.

Out of scope (explicitly): Events/Show web page (works as built — earlier
report was a server caching issue); booking-flow EventDetails.vue; any
version bump (mobile changes ride the 1.23 train — one bump per train).

## 1. Proximity-sorted, searchable link pickers (mobile + web)

Shared behavior on both platforms:

- With a check-in date set, event options sort by `|event.date − check_in|`
  and group: **"During your stay"** (event date within check-in..check-out),
  then **"Nearby"** (within ±14 days), then **"Everything else"** (date
  ascending from today). Without a check-in, sort date-ascending from today.
- A text filter above the list matches on title/name.
- Mobile: the `CupertinoPicker` wheels for booking and event are replaced
  by a searchable bottom-sheet list (title + formatted date per row).
  Sheet re-attaches provider scope (`UncontrolledProviderScope`).
- Web: the two plain `<select>`s in `Lodging/Form.vue` are replaced by a
  small filterable-list component with the same grouping.
- Sorting/grouping is computed client-side on both platforms from the
  option payloads; no new endpoints.

Backend (small): the bookings picker payload (`LodgingController::create`
/`edit`, mobile equivalents if present) currently sends `{id, name}`
ordered by `created_at` desc. Bookings no longer carry dates (they moved
to events), so each booking option gains `date` = its nearest event date
(min upcoming, else max past), enabling proximity sorting for bookings.

## 2. Lodging on the mobile dashboard calendar

- Source: the existing `lodgingsProvider(bandId)` list. Client-side
  expansion into a `lodgingByDay` map covering every day from check-in
  through check-out (inclusive, day-normalised like `eventsByDay`).
- Marker: a distinct lodging marker (bed glyph / dedicated color) on every
  covered day, composed alongside existing `CalendarDayMarkers`.
- Agenda: each covered day's list gets a lodging row — hotel name, plus
  the actual time on boundary days ("Check-in 3:00 PM" / "Check-out
  11:00 AM"), plain "Staying at <name>" on middle days. Tap →
  `context.push('/lodging/<id>')`.
- Filter: a "Lodging" toggle in the existing calendar filter sheet,
  persisted the same way as current filters.
- No windowing work: the lodging list is fetched whole. Realtime
  invalidation for the `lodging` model is already wired.

## 3. Web advance page: logistics-only lodging + artifact removal

- Remove `Advance.vue:231-239` (the `v-if="(event.lodging)"` legacy block).
  The legacy scalar itself stays in the data/model (other legacy surfaces
  untouched).
- New advance lodging section fed by a `lodgings` array on the advance
  payload, produced by a new `LodgingService::formatLogistics(Lodging)`:
  **name, address, check_in_at, check_out_at, room_count — nothing else.**
  No confirmation numbers, notes, or attachment URLs, because advance
  links are passed around and the route is intentionally loose (#567).
  The restriction lives server-side in the formatter, not in the template.
- Stays shown: the event's linked stays (`$event->lodgings()`), ordered by
  check-in.

## 4. Web dashboard event cards

- Events on the dashboard feed that have linked stays get one compact
  line on their `EventCard`: bed icon, hotel name, check-in time, linking
  to `lodgings.show`.
- Backend: the dashboard events payload gains the same
  `formatLogistics()` summary per event (members-only surface; reuse the
  formatter — id + name + check_in_at suffice for the card, and
  `formatLogistics` already carries them).

## 5. Mobile event detail: at-a-glance card + logistics-first reorder

- Header tightening:
  - The labeled Status row ("Status" + Confirmed pill) is removed; status
    becomes a small colored dot beside the event title (same idiom as the
    Roster section's dot): green confirmed, and the other status values
    keep their existing pill colors as dot colors. Dot carries a
    semantic label for accessibility.
  - The boolean chips (Private / Outdoor / Backline / Production) render
    as one compact single-line row — smaller padding/font, horizontally
    scrollable if they ever overflow 320pt — instead of wrapping to two
    rows.
- New compact summary card directly under the tightened header block
  (Go-to-booking / date / venue-map card / chips row otherwise
  unchanged; the map card already covers venue, so the summary does NOT
  repeat it):
  - show time (same source as the Timeline's injected Show Time row),
  - attire one-liner (first line, ellipsized),
  - lodging one-liner "🛏 <name> · check-in <time>" (when linked stays
    exist; tap → `/lodging/<id>`, first stay if several).
  Rows render only when their data exists — the card collapses to
  whatever is known.
- Section reorder below: Timeline, Attire, Setlist button, Lodging,
  Contacts, Roster, Performance, Wedding Details, Notes, Attachments,
  Media — reference material moves below the people/logistics sections.
- Verbose-content collapsing (the real screen-length culprits):
  - Notes taller than ~6 lines render clamped with a "Show more" /
    "Show less" toggle.
  - Attachments beyond the first 3 collapse behind "Show all (N)".
  Both default collapsed on entry; state is per-visit (not persisted).
- Pure presentation change: no payload or provider changes. 320pt-safe.

## Testing

- PHP: advance payload test asserting the logistics fields are present
  AND that confirmation_number/notes/attachment url substrings are absent
  from the response; dashboard payload test; bookings-option date test
  (nearest-event derivation, booking with no events → null date sorts
  last).
- Vitest: picker component (grouping + filter), advance section render,
  event-card lodging line (assert on text, not v-if markers).
- Flutter: unit test for the day-expansion map (relative dates, inclusive
  boundaries, multi-stay overlap) and picker grouping; widget tests at
  `Size(320, 568)` for the summary card (rows collapse when data absent)
  and a calendar day with a lodging marker + agenda row; filter-toggle
  test; notes-clamp toggle test (long note collapsed by default, expands
  on tap) and attachments show-all test.

## Rollout

1. TTS PR, base `staging` (payload additions are additive; advance
   artifact removal is web-only).
2. Mobile PR, base `main`, after the TTS PR deploys. Rides the open 1.23
   train — **no version bump** (one bump per train; release PR #135 stays
   open until store release).
