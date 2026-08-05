# Lodging Adjustments — Mobile Plan (tts_bandmate repo)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Proximity-sorted searchable link pickers, lodging on the dashboard calendar, and the event-detail redesign (⋯ menu, status dot, one-line chips, at-a-glance card, notes+attachments bundle, roster row → full-screen sheet, logistics-first order) per the approved v6 mockup.

**Architecture:** Pure-Dart grouping/expansion utils (unit-testable, no widgets); the picker sheet and roster sheet are relocations of existing plumbing; the event-detail redesign is presentation-only — no payload, provider, or backend changes anywhere in this plan.

**Tech Stack:** Flutter/Cupertino, Riverpod v2, intl, go_router.

**Repo:** `/home/eddie/github/tts_bandmate`, fresh branch `feat/lodging-adjustments` off up-to-date `main`. PR base `main`.

## Global Constraints

- **NO version bump** — this rides the open 1.23 train (one bump per train; release PR #135 stays open).
- Text colors via `context.secondaryText`/`primaryText`/`tertiaryText` — never raw `CupertinoColors.*Label` in a `color:`.
- All layouts verified at `Size(320, 568)`; long names wrap or ellipsize.
- Test dates computed relative to `DateTime.now()` — never hardcoded.
- Sheets/popups opened from screens that read providers must re-attach scope: `UncontrolledProviderScope(container: ProviderScope.containerOf(context), ...)`.
- `/lodging` routes are OUTSIDE the nav shell — navigate with `context.push`, never `context.go` (go strands users with no tabs/back).
- `flutter analyze` clean (4 pre-existing warnings allowed, none new) and `flutter test` green before every commit. Conventional commits.

---

### Task 1: Link-picker grouping util + searchable sheet

**Files:**
- Create: `lib/features/lodging/utils/link_picker_options.dart`
- Modify: `lib/features/lodging/screens/lodging_edit_screen.dart:222-320` (`_bookingOptions`/`_eventOptions`/`_showOptionPicker`)
- Test: `test/features/lodging/link_picker_options_test.dart`

**Interfaces:**
- Consumes: `_bookings` (`List<BookingSummary>` with nested `.events`, each event has `id`, `title`, `date` string + `parsedDate`; bookings have `id`, `name` — booking dates derive from their events' min upcoming date, computed here client-side). `_checkIn`/`_checkOut` are `DateTime?` state on the screen.
- Produces:
  - `class LinkOption { final int? id; final String label; final DateTime? date; const LinkOption(this.id, this.label, [this.date]); }`
  - `List<({String label, List<LinkOption> options})> groupLinkOptions(List<LinkOption> options, DateTime? checkIn, DateTime? checkOut)` — groups `During your stay` (date within checkIn..checkOut, day-granularity) / `Nearby` (±14 days of check-in) / `Everything else`; within the first two sorted by |date − checkIn|, the rest date-ascending with undated last; empty groups omitted. Null checkIn → single `('', options)` group date-ascending, undated last.
  - Screen change: `_showOptionPicker` becomes a searchable list sheet (filter field + grouped rows) used by both pickers; same `onSelected(int?)` contract; "None" row pinned on top outside groups.

- [ ] **Step 1: Failing util test**

```dart
// test/features/lodging/link_picker_options_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/lodging/utils/link_picker_options.dart';

void main() {
  final checkIn = DateTime.now().add(const Duration(days: 30));
  final checkOut = checkIn.add(const Duration(days: 3));

  LinkOption opt(int id, String label, DateTime? date) =>
      LinkOption(id, label, date);

  group('groupLinkOptions', () {
    test('groups during / nearby / rest', () {
      final groups = groupLinkOptions([
        opt(1, 'Far', checkIn.add(const Duration(days: 60))),
        opt(2, 'During', checkIn.add(const Duration(days: 1))),
        opt(3, 'Near', checkIn.subtract(const Duration(days: 9))),
        opt(4, 'Undated', null),
      ], checkIn, checkOut);

      expect(groups.map((g) => g.label).toList(),
          ['During your stay', 'Nearby', 'Everything else']);
      expect(groups[0].options.single.id, 2);
      expect(groups[1].options.single.id, 3);
      expect(groups[2].options.map((o) => o.id).toList(), [1, 4]);
    });

    test('nearby sorted by distance from check-in', () {
      final groups = groupLinkOptions([
        opt(1, 'Nine off', checkIn.add(const Duration(days: 9))),
        opt(2, 'Two off', checkIn.subtract(const Duration(days: 2))),
      ], checkIn, checkOut);
      expect(groups.single.label, 'Nearby');
      expect(groups.single.options.map((o) => o.id).toList(), [2, 1]);
    });

    test('no check-in: single ascending group, undated last', () {
      final groups = groupLinkOptions([
        opt(1, 'B', DateTime.now().add(const Duration(days: 20))),
        opt(2, 'A', DateTime.now().add(const Duration(days: 5))),
        opt(3, 'U', null),
      ], null, null);
      expect(groups, hasLength(1));
      expect(groups.single.options.map((o) => o.id).toList(), [2, 1, 3]);
    });
  });
}
```

- [ ] **Step 2: Run to verify failure** — `flutter test test/features/lodging/link_picker_options_test.dart` — FAIL (file missing).

- [ ] **Step 3: Implement util**

```dart
// lib/features/lodging/utils/link_picker_options.dart

/// One selectable row in the booking/event link pickers.
class LinkOption {
  const LinkOption(this.id, this.label, [this.date]);
  final int? id;
  final String label;
  final DateTime? date;
}

DateTime? _day(DateTime? dt) =>
    dt == null ? null : DateTime(dt.year, dt.month, dt.day);

const _nearbyDays = 14;

/// Groups options around a stay: "During your stay" (inside
/// check-in..check-out), "Nearby" (±14 days of check-in), then everything
/// else. Empty groups are omitted. Without a check-in, one unlabeled group
/// sorted date-ascending, undated entries last.
List<({String label, List<LinkOption> options})> groupLinkOptions(
  List<LinkOption> options,
  DateTime? checkIn,
  DateTime? checkOut,
) {
  final inDay = _day(checkIn);
  final outDay = _day(checkOut) ?? inDay;

  int ascending(LinkOption a, LinkOption b) {
    final da = _day(a.date);
    final db = _day(b.date);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  if (inDay == null) {
    final sorted = [...options]..sort(ascending);
    return [(label: '', options: sorted)];
  }

  int distance(LinkOption o) =>
      _day(o.date)!.difference(inDay).inDays.abs();

  final during = <LinkOption>[];
  final nearby = <LinkOption>[];
  final rest = <LinkOption>[];
  for (final o in options) {
    final day = _day(o.date);
    if (day != null && !day.isBefore(inDay) && !day.isAfter(outDay!)) {
      during.add(o);
    } else if (day != null && distance(o) <= _nearbyDays) {
      nearby.add(o);
    } else {
      rest.add(o);
    }
  }
  during.sort((a, b) => distance(a).compareTo(distance(b)));
  nearby.sort((a, b) => distance(a).compareTo(distance(b)));
  rest.sort(ascending);

  return [
    (label: 'During your stay', options: during),
    (label: 'Nearby', options: nearby),
    (label: 'Everything else', options: rest),
  ].where((g) => g.options.isNotEmpty).toList();
}
```

- [ ] **Step 4: Screen rewiring.** In `lodging_edit_screen.dart`:
  - `_bookingOptions` → `List<LinkOption>`: booking date = min event date `>= today` else max event date (compute from `b.events`, parse via `e.parsedDate`; empty events → null date). Label stays `b.name`.
  - `_eventOptions` → `List<LinkOption>` with `date: e.parsedDate`, label `e.title` (date now rendered by the sheet row, not baked into the label).
  - Replace `_showOptionPicker`'s `CupertinoPicker` body with a searchable sheet (height ~520 or `DraggableScrollableSheet`-style fixed 0.75 height `Container`): a `CupertinoSearchTextField` on top (filter on `label`, case-insensitive), then a `ListView` rendering a pinned "None" row followed by `groupLinkOptions(filtered, _checkIn, _checkOut)` — group headers in `context.secondaryText` 13pt uppercase, option rows showing label (primary) + `DateFormat('EEE, MMM d, yyyy')` date (secondary, when non-null), a checkmark on the row whose id == selectedId. Tapping a row calls `onSelected(id)` and pops immediately (no Done button). Keep the `UncontrolledProviderScope` wrapper exactly as-is.

- [ ] **Step 5: Run + analyze** — `flutter test test/features/lodging/ && flutter analyze` — PASS/clean.

- [ ] **Step 6: Commit**

```bash
git add lib test
git commit -m "feat(lodging): proximity-grouped searchable link pickers"
```

---

### Task 2: Lodging on the dashboard calendar

**Files:**
- Create: `lib/features/lodging/utils/lodging_by_day.dart`
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart` (~:320-365 build section, `_CalendarSection` :421-436, the agenda day-list renderer)
- Modify: `lib/features/dashboard/providers/calendar_filter_provider.dart` (add lodging visibility)
- Modify: `lib/features/dashboard/widgets/calendar_filter_sheet.dart` (Lodging toggle row)
- Modify: `lib/features/dashboard/widgets/calendar_event_marker.dart` (lodging marker variant)
- Test: `test/features/lodging/lodging_by_day_test.dart`, `test/features/dashboard/calendar_lodging_widget_test.dart`

**Interfaces:**
- Consumes: `lodgingsProvider(bandId)` (`AsyncNotifierProvider.family<LodgingsNotifier, ({List<LodgingSummary> lodgings, bool canWrite}), int>`), `LodgingSummary` (`id`, `name`, `checkInAt`/`checkOutAt` raw strings + `parsedCheckIn`), `selectedBandProvider`, `calendarFilterProvider`.
- Produces:
  - `class LodgingDayEntry { final LodgingSummary lodging; final bool isCheckIn; final bool isCheckOut; }`
  - `Map<DateTime, List<LodgingDayEntry>> lodgingByDay(List<LodgingSummary> stays)` — one entry per stay per covered day (check-in through check-out inclusive, day-normalised `DateTime(y,m,d)` keys; malformed dates skipped; check-in==check-out yields one day flagged both).
  - `CalendarFilterState` gains `hideLodging` (bool, default false) + `isLodgingVisible` getter + `toggleLodging()`; `isActive`/`activeCount` include it.
  - Agenda rows: "Check-in 3:00 PM · <name>" / "Check-out 11:00 AM · <name>" on boundary days, "Staying at <name>" on middle days; tap → `context.push('/lodging/<id>')`.

- [ ] **Step 1: Failing util test**

```dart
// test/features/lodging/lodging_by_day_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';
import 'package:tts_bandmate/features/lodging/utils/lodging_by_day.dart';

LodgingSummary _stay(int id, DateTime checkIn, DateTime checkOut) =>
    LodgingSummary(
      id: id,
      name: 'Stay $id',
      checkInAt: checkIn.toIso8601String(),
      checkOutAt: checkOut.toIso8601String(),
      roomCount: 1,
      attachmentCount: 0,
    );

void main() {
  test('expands inclusive day range with boundary flags', () {
    final checkIn = DateTime.now().add(const Duration(days: 10, hours: 15));
    final checkOut = checkIn.add(const Duration(days: 2)); // 3 covered days
    final map = lodgingByDay([_stay(1, checkIn, checkOut)]);

    expect(map, hasLength(3));
    final firstDay = DateTime(checkIn.year, checkIn.month, checkIn.day);
    expect(map[firstDay]!.single.isCheckIn, isTrue);
    expect(map[firstDay]!.single.isCheckOut, isFalse);
    final midDay = firstDay.add(const Duration(days: 1));
    expect(map[midDay]!.single.isCheckIn, isFalse);
    expect(map[midDay]!.single.isCheckOut, isFalse);
    final lastDay = firstDay.add(const Duration(days: 2));
    expect(map[lastDay]!.single.isCheckOut, isTrue);
  });

  test('overlapping stays stack on shared days', () {
    final a = DateTime.now().add(const Duration(days: 5, hours: 15));
    final map = lodgingByDay([
      _stay(1, a, a.add(const Duration(days: 2))),
      _stay(2, a.add(const Duration(days: 1)), a.add(const Duration(days: 3))),
    ]);
    final sharedDay = DateTime(a.year, a.month, a.day).add(const Duration(days: 1));
    expect(map[sharedDay], hasLength(2));
  });

  test('same-day stay flags both boundaries; malformed dates skipped', () {
    final a = DateTime.now().add(const Duration(days: 4, hours: 15));
    final map = lodgingByDay([
      _stay(1, a, a.add(const Duration(hours: 2))),
      const LodgingSummary(
          id: 9, name: 'Broken', checkInAt: 'garbage', checkOutAt: '',
          roomCount: 0, attachmentCount: 0),
    ]);
    expect(map, hasLength(1));
    expect(map.values.single.single.isCheckIn, isTrue);
    expect(map.values.single.single.isCheckOut, isTrue);
  });
}
```
(`LodgingSummary.parsedCheckIn` falls back to `DateTime.now()` on garbage — the util must therefore parse with `DateTime.tryParse` on the RAW strings and skip nulls, not use the fallback getter.)

- [ ] **Step 2: Run to verify failure** — FAIL (file missing).

- [ ] **Step 3: Implement util**

```dart
// lib/features/lodging/utils/lodging_by_day.dart
import '../data/models/lodging.dart';

class LodgingDayEntry {
  const LodgingDayEntry({
    required this.lodging,
    required this.isCheckIn,
    required this.isCheckOut,
  });
  final LodgingSummary lodging;
  final bool isCheckIn;
  final bool isCheckOut;
}

DateTime _day(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Expands stays into per-day calendar entries, check-in through
/// check-out inclusive. Uses tryParse on the raw wire strings —
/// parsedCheckIn's now() fallback would invent phantom entries for
/// malformed data.
Map<DateTime, List<LodgingDayEntry>> lodgingByDay(
    List<LodgingSummary> stays) {
  final map = <DateTime, List<LodgingDayEntry>>{};
  for (final stay in stays) {
    final checkIn = DateTime.tryParse(stay.checkInAt);
    final checkOut = DateTime.tryParse(stay.checkOutAt);
    if (checkIn == null || checkOut == null) continue;
    var day = _day(checkIn);
    final lastDay = _day(checkOut);
    if (lastDay.isBefore(day)) continue;
    while (!day.isAfter(lastDay)) {
      map.putIfAbsent(day, () => []).add(LodgingDayEntry(
            lodging: stay,
            isCheckIn: day == _day(checkIn),
            isCheckOut: day == lastDay,
          ));
      day = day.add(const Duration(days: 1));
    }
  }
  return map;
}
```
(Adding `const` constructor + const-usable fields to `LodgingSummary` is allowed if the test's `const LodgingSummary(...)` needs it and the class lacks one — check first; otherwise drop `const` in the test.)

- [ ] **Step 4: Filter state.** In `calendar_filter_provider.dart`: add `final bool hideLodging;` (default `false`) to `CalendarFilterState` (constructor, `copyWith`, `==`/`hashCode`, `isActive` → `|| hideLodging`, `activeCount` → `+ (hideLodging ? 1 : 0)`); notifier gains `void toggleLodging() => state = state.copyWith(hideLodging: !state.hideLodging);`. In `calendar_filter_sheet.dart`, add a "Lodging" toggle row alongside the event-type rows (copy an existing row's widget exactly, wired to `notifier.toggleLodging()` / `filter.hideLodging`).

- [ ] **Step 5: Dashboard wiring.** In `dashboard_screen.dart` (~:324-332):

```dart
    final bandId = ref.watch(selectedBandProvider).value;
    final lodgingState =
        bandId == null ? null : ref.watch(lodgingsProvider(bandId)).value;
    final lodgingDays = (filterState.hideLodging || lodgingState == null)
        ? const <DateTime, List<LodgingDayEntry>>{}
        : lodgingByDay(lodgingState.lodgings);
```
Guard: a 403/error from `lodgingsProvider` must never break the dashboard — `.value` on the AsyncValue is null on error, which the null-check already handles (feature-hidden semantics). Pass `lodgingDays` into `_CalendarSection` (new required param `Map<DateTime, List<LodgingDayEntry>> lodgingByDay`) and into the agenda renderer for the selected day.
  - Marker: in `_CalendarSection`'s day builder, when `lodgingByDay[day]` is non-empty, compose a lodging marker alongside `CalendarDayMarkers` — add a `hasLodging` param to `CalendarDayMarkers` (`calendar_event_marker.dart:57`) rendering one extra dot in a distinct color (`CupertinoColors.systemIndigo`) or a 7pt `CupertinoIcons.bed_double` glyph — read the existing marker composition and match its sizing.
  - Agenda: where the selected day's `EventSummary` rows render, append lodging rows after event rows: leading `CupertinoIcons.bed_double` (`context.secondaryText`), text per the boundary rules (times via `DateFormat('h:mm a')` on the parsed raw string), chevron, `onTap: () => context.push('/lodging/${entry.lodging.id}')`.

- [ ] **Step 6: Widget test.** `test/features/dashboard/calendar_lodging_widget_test.dart`: pump the dashboard (or the extracted `_CalendarSection` if the full screen needs too many fakes — check how existing dashboard widget tests pump, grep `test/features/dashboard/`) with a fake lodging repo returning one stay covering `now()+3d..now()+5d` at 320pt; assert the agenda for the check-in day shows "Check-in" and the stay name; toggle `hideLodging` via the provider and assert it disappears.

- [ ] **Step 7: Run + analyze + commit**

```bash
flutter test && flutter analyze
git add lib test
git commit -m "feat(lodging): stays on the dashboard calendar with filter toggle"
```

---

### Task 3: Event detail — header, ⋯ menu, at-a-glance card

**Files:**
- Modify: `lib/features/events/screens/event_detail_screen.dart:105-165` (nav bar, booking link row, status row, flags row)
- Create: `lib/features/events/widgets/event_glance_card.dart`
- Test: `test/features/events/event_detail_redesign_test.dart` (new; grep existing event-detail widget tests for the pump scaffolding and reuse their fakes)

**Interfaces:**
- Consumes: `EventDetail` fields — `title`, `status`, `time`, `endTime`, `attire`, `lodgings` (`List<LodgingSummary>`), `canWrite`, `key`, `eventableType`/`eventableId` (booking link), `isPublic`/`outside`/`backlineProvided`/`productionNeeded` (chips).
- Produces:
  - Nav `middle`: `Row(mainAxisSize: MainAxisSize.min)` of status dot + title. Dot: 9pt circle, color by status (`confirmed` → `CupertinoColors.systemGreen`; map the other values from the existing `StatusChip` widget's color mapping — read it and reuse its color fn, extracting `Color statusColor(String status)` if private). Wrap in `Semantics(label: 'Status: <status>')`. No dot when status null.
  - Nav `trailing`: ⋯ button (`CupertinoIcons.ellipsis_circle`) → `showCupertinoModalPopup` + `CupertinoActionSheet` with actions: "Go to booking" (only when booking-backed; same push as the removed `PartOfBookingRow`), "Go to roster" (opens the roster sheet — Task 5 wires the real call; until then scrolls: leave a `_openRoster()` indirection), "Setlist" (`context.push('/events/${event.key}/setlist')`), "Edit event" (only when `canWrite`; existing push), plus a cancel button. Wrap the sheet in `UncontrolledProviderScope`.
  - Body deletions: `PartOfBookingRow` block (:122-131), the Status `_InfoRow` (:150-158). `_FlagsRow` (:505-536): replace the `Wrap` with a horizontal `SingleChildScrollView` + `Row`, chip font 12, padding 4×10.
  - `EventGlanceCard(event: event, onShowTimeTap, onLodgingTap)` inserted after `_FlagsRow`: rows per spec — show time ("Show 6:30 PM" + "ends 10:00 PM" trailing when `endTime` set; reuse the screen's existing time formatting helpers), attire (collapsed: label "Attire" + rotated-when-open chevron; expanded: full `event.attire` text inline, `AnimatedCrossFade` or simple conditional), lodging (first stay name, tap → `context.push('/lodging/${lodging.id}')`). Rows only when data exists; card hidden entirely when all empty. Hairline separators `CupertinoColors.separator.resolveFrom(context)`.

- [ ] **Step 1: Failing widget tests** — in `test/features/events/event_detail_redesign_test.dart`, pumping the screen with the existing fake-repo scaffolding (copy from the newest event-detail test file):
  - `menu shows booking, roster, setlist actions and edit only when canWrite` (tap ellipsis, assert action texts; pump with canWrite=false → no "Edit event").
  - `status renders as dot not labeled row` (assert `find.text('Status')` findsNothing; `find.bySemanticsLabel(RegExp('Status: confirmed'))` findsOneWidget).
  - `glance card shows show time, attire expands inline, lodging navigates` (attire text absent → tap attire row → text visible; assert lodging name row exists).
  - All at `tester.view.physicalSize = const Size(320, 568)`.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** per the Produces block. Keep deleted widgets' code out (delete `PartOfBookingRow` usage here; the widget class itself may have other users — grep before deleting the class).
- [ ] **Step 4: Run + analyze.**
- [ ] **Step 5: Commit** — `feat(events): overflow menu, status dot, one-line chips, at-a-glance card`

---

### Task 4: Event detail — notes+attachments bundle and reorder

**Files:**
- Modify: `lib/features/events/screens/event_detail_screen.dart:170-260` (section order), the Notes section widget, `_AttachmentsSection` (:1618+)
- Test: extend `test/features/events/event_detail_redesign_test.dart`

**Interfaces:**
- Consumes: existing `_AttachmentsSection`, notes rendering, `_SetlistRow`/`_LiveSetlistButton` (:792-855).
- Produces:
  - Combined section: `_SectionHeader(title: 'Notes')` (header text stays "Notes") containing: clamped note text (`maxLines: 6, overflow: TextOverflow.ellipsis` + a "Show more"/"Show less" `CupertinoButton` shown only when the text exceeds 6 lines — measure with `TextPainter` or a `LayoutBuilder`; simplest robust approach: always render the toggle when `'\n'.allMatches(notes).length + notes.length ~/ 40 > 6`), then the attachments list capped at 3 rows + "Show all (N)" toggle (local state), inside the same card region. Renders when notes non-empty OR attachments non-empty.
  - New body order: glance card → Notes(+attachments) → Timeline → Lodging → Contacts → Roster → Performance → Wedding Details → Media. The standalone Attire section block (:210-214) and the plain `_SetlistRow` are REMOVED (attire lives in the glance card; Setlist lives in the ⋯ menu). `_LiveSetlistButton` ("Join Live Setlist") STAYS in the body at its current position when a live session is active — it is a state-driven call-to-action, not navigation chrome.
- [ ] **Step 1: Failing tests** — long-note fixture (20 lines): collapsed by default (`find.text('Show more')` present, line 15's text not hit-testable is hard — assert toggle presence and that tapping flips to "Show less"); attachments fixture with 5 files: exactly 3 filename rows + "Show all (5)"; section order: `find.text('Timeline')` appears BELOW `find.text('Notes')` (compare `tester.getTopLeft` y-coordinates); `find.text('Attire')` as a section header findsNothing; setlist row absent from body.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run + analyze.**
- [ ] **Step 5: Commit** — `feat(events): bundle notes+attachments, logistics-first section order`

---

### Task 5: Roster row + full-screen roster sheet

**Files:**
- Create: `lib/features/events/screens/roster_sheet.dart`
- Modify: `lib/features/events/screens/event_detail_screen.dart` (`_RosterSection` :1763+ → summary row; `_openRoster()` from Task 3)
- Test: extend `test/features/events/event_detail_redesign_test.dart`

**Interfaces:**
- Consumes: everything `_RosterSection`/`_RosterSectionState` uses today — `event.members` (grouped by `m.groupKey`), `event.rosterStatus`, `_MemberTile`, `onAssignSub`/`_showSubPicker`, status-change plumbing, `canWrite`. Move, don't rewrite.
- Produces:
  - `RosterSheet` — full-screen (`CupertinoPageRoute(fullscreenDialog: true)`) `ConsumerStatefulWidget` with `CupertinoNavigationBar(middle: Text('Event Roster'), trailing: close X)`, a subtitle line "<event title> · <EEE, MMM d>", and the existing grouped member list + controls relocated verbatim (groups, role labels, SUB badges, status chips, ＋ empty-slot rows if the current section renders them, sub picker — all behavior identical, canWrite gates preserved). Sub-picker popups inside the sheet re-attach provider scope.
  - Summary row replacing `_RosterSection`'s body: `👥` icon, "<confirmed+pending count> members" or "N + M sub" (derive counts from `event.members`: total, subs where the member is a sub-slot, unconfirmed where attendance_status is pending/unset — reuse the exact status logic `_RosterSectionState` used for `rosterStatus` colors), attention dot (`CupertinoColors.systemOrange`) + subtitle "N awaiting confirmation" when any pending, chevron, tap → push `RosterSheet`. `_openRoster()` from Task 3's menu pushes the same sheet.
- [ ] **Step 1: Failing tests** — summary row shows count + "awaiting confirmation" subtitle from a fixture with 2 pending members; tapping the row opens a screen containing a grouped member name; menu "Go to roster" opens the same sheet.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** (move code; `git diff` should show relocation, not rewrites).
- [ ] **Step 4: Run + analyze.**
- [ ] **Step 5: Commit** — `feat(events): roster summary row + full-screen roster sheet`

---

### Task 6: Full suite, on-device verify, PR

- [ ] **Step 1:** `flutter test && flutter analyze` — full suite green, no new analyzer issues.
- [ ] **Step 2:** On-device (run-on-device skill) against local backend: open an event with long notes + attachments + lodging + roster — verify menu actions, status dot, chips on one line at real width, glance card taps (attire expand, lodging nav, show-time scroll), notes/attachments toggles, roster sheet controls (status change + sub assign), calendar lodging markers/agenda/filter, and the new link picker (search + groups). Screenshot the redesigned event detail, calendar with lodging, and picker sheet.
- [ ] **Step 3:** Push + PR (base `main`, after the TTS surfaces PR merges):
```bash
git push -u origin feat/lodging-adjustments
gh pr create --base main --title "feat: lodging surfaces + event detail redesign" --body "$(cat <<'EOF'
## Summary
- Booking/event link pickers: searchable sheet grouped by date proximity (During your stay / Nearby / rest)
- Dashboard calendar: lodging markers on every covered day, agenda rows with check-in/out times, filter toggle
- Event detail redesign: ⋯ menu (booking/roster/setlist/edit), status dot on title, one-line chips, at-a-glance card (show time, inline-expanding attire, lodging), notes+attachments bundled and clamped, logistics-first order, roster row + full-screen roster sheet

No version bump — rides the open 1.23 train.

## Test plan
- [ ] Unit: link_picker_options, lodging_by_day
- [ ] Widget: menu/status/glance, notes clamp + attachments show-all, roster row/sheet, calendar lodging + filter — all at 320pt
- [ ] On-device verify with screenshots

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_014HjpXvYak8CfXzEH1sVKh7
EOF
)"
```
- [ ] **Step 4:** Wait for Copilot review and address comments before calling it done.
