# Bookings Screen Styling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Bookings screen visually consistent with the Library screen pattern (bottom search + add bar, floating filter button, filter sheet) and replace the broken year stepper / auto-scroll with a horizontal month-chip strip + key-based scroll-to-nearest-upcoming.

**Architecture:** Mirrors `lib/features/library/`'s file layout: a Riverpod `Notifier` for filter state, dedicated widgets for the floating filter button + filter sheet, pure helpers extracted into testable functions, and a single screen widget that composes everything. The bookings provider drops its `year` parameter; all year filtering is moved client-side.

**Tech Stack:** Flutter 3 / Cupertino, Riverpod v2, intl, flutter_test.

**Spec:** `docs/superpowers/specs/2026-05-02-bookings-styling-design.md`

---

## File Structure

**Create:**
- `lib/features/bookings/data/models/booking_status.dart` — `BookingStatus` enum + label extension.
- `lib/features/bookings/providers/bookings_filter_provider.dart` — `BookingsFilterState`, `BookingsFilterNotifier`, `bookingsFilterProvider`.
- `lib/features/bookings/utils/booking_search.dart` — `bookingMatchesQuery(BookingSummary, String)` pure helper.
- `lib/features/bookings/utils/booking_month_strip.dart` — `monthKey(DateTime)`, `buildMonthKeys(List<BookingSummary>)`, `findNearestUpcomingIndex(List<BookingSummary>, DateTime)` pure helpers.
- `lib/features/bookings/widgets/bookings_filter_button.dart` — floating circular filter button (mirrors `LibraryFilterButton`).
- `lib/features/bookings/widgets/bookings_filter_sheet.dart` — bottom-sheet filter modal (status pills + bands row).
- `lib/features/bookings/widgets/bookings_month_strip.dart` — pinned horizontal month-chip strip widget + `SliverPersistentHeaderDelegate`.
- `lib/features/bookings/widgets/bookings_bottom_bar.dart` — bottom search-and-add bar (mirrors Library's `_BottomSearchBar`).
- `test/features/bookings/providers/bookings_filter_provider_test.dart`
- `test/features/bookings/utils/booking_search_test.dart`
- `test/features/bookings/utils/booking_month_strip_test.dart`
- `test/features/bookings/widgets/bookings_filter_button_test.dart`
- `test/features/bookings/widgets/bookings_filter_sheet_test.dart`

**Modify:**
- `lib/features/bookings/screens/bookings_screen.dart` — full rewrite of the screen body; deletes `_StickyControls`, `_FilterPills`, `_YearStepper`, `_BookingsFilter` enum.
- `lib/features/bookings/providers/bookings_provider.dart` — drop `year` from `UserBookingsParams` (or replace with parameterless provider). Keep `BandBookingsParams` untouched for callers we don't own.
- `lib/features/bookings/data/bookings_repository.dart` — `getAllUserBookings` no longer requires `year` (already optional; this just confirms the call site stops passing it).
- `lib/features/library/screens/library_screen.dart` — fix floating filter button position (`top: MediaQuery.padding.top + 50` instead of `_kFilterButtonTopInset = 8.0`).
- `test/providers/user_bookings_provider_test.dart` — update for the parameterless / no-year provider shape.
- `test/features/bookings/bookings_screen_multi_band_test.dart` — update to the new screen shape (status filter via provider, no year stepper).

---

## Task 1: Add `BookingStatus` enum

**Files:**
- Create: `lib/features/bookings/data/models/booking_status.dart`

- [ ] **Step 1: Create the file**

```dart
/// Status filter applied to the Bookings list.
///
/// `all` is the no-filter sentinel — selecting it shows every booking.
enum BookingStatus { all, confirmed, pending, draft }

extension BookingStatusLabel on BookingStatus {
  String get label => switch (this) {
        BookingStatus.all => 'All',
        BookingStatus.confirmed => 'Confirmed',
        BookingStatus.pending => 'Pending',
        BookingStatus.draft => 'Draft',
      };

  /// Lowercase API-style key, used to compare against `BookingSummary.status`.
  String? get apiKey => switch (this) {
        BookingStatus.all => null,
        BookingStatus.confirmed => 'confirmed',
        BookingStatus.pending => 'pending',
        BookingStatus.draft => 'draft',
      };
}
```

- [ ] **Step 2: Verify it analyzes**

Run: `flutter analyze lib/features/bookings/data/models/booking_status.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/bookings/data/models/booking_status.dart
git commit -m "feat(bookings): add BookingStatus enum"
```

---

## Task 2: Add `bookingsFilterProvider`

**Files:**
- Create: `lib/features/bookings/providers/bookings_filter_provider.dart`
- Test: `test/features/bookings/providers/bookings_filter_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/bookings/providers/bookings_filter_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_status.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_filter_provider.dart';

void main() {
  group('BookingsFilterState', () {
    test('default state is not active', () {
      const state = BookingsFilterState();
      expect(state.status, BookingStatus.all);
      expect(state.hiddenBandIds, isEmpty);
      expect(state.isActive, false);
      expect(state.activeCount, 0);
    });

    test('non-all status counts as 1 active', () {
      const state = BookingsFilterState(status: BookingStatus.confirmed);
      expect(state.isActive, true);
      expect(state.activeCount, 1);
    });

    test('hidden bands count toward activeCount', () {
      const state = BookingsFilterState(hiddenBandIds: {1, 2});
      expect(state.activeCount, 2);
    });

    test('status + hidden bands sum', () {
      const state = BookingsFilterState(
        status: BookingStatus.pending,
        hiddenBandIds: {7},
      );
      expect(state.activeCount, 2);
    });

    test('value-equality on identical state', () {
      const a = BookingsFilterState(
        status: BookingStatus.draft,
        hiddenBandIds: {1, 2},
      );
      const b = BookingsFilterState(
        status: BookingStatus.draft,
        hiddenBandIds: {1, 2},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('BookingsFilterNotifier', () {
    test('setStatus updates status', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(bookingsFilterProvider.notifier)
          .setStatus(BookingStatus.confirmed);

      expect(container.read(bookingsFilterProvider).status,
          BookingStatus.confirmed);
    });

    test('toggleBand adds and removes a band id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(bookingsFilterProvider.notifier);
      notifier.toggleBand(5);
      expect(container.read(bookingsFilterProvider).hiddenBandIds, {5});

      notifier.toggleBand(5);
      expect(container.read(bookingsFilterProvider).hiddenBandIds, isEmpty);
    });

    test('clear resets state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(bookingsFilterProvider.notifier);
      notifier.setStatus(BookingStatus.pending);
      notifier.toggleBand(1);
      notifier.toggleBand(2);
      expect(container.read(bookingsFilterProvider).isActive, true);

      notifier.clear();
      final state = container.read(bookingsFilterProvider);
      expect(state.status, BookingStatus.all);
      expect(state.hiddenBandIds, isEmpty);
      expect(state.isActive, false);
    });
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/features/bookings/providers/bookings_filter_provider_test.dart`
Expected: FAIL — `bookingsFilterProvider` not defined.

- [ ] **Step 3: Implement the provider**

```dart
// lib/features/bookings/providers/bookings_filter_provider.dart
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/booking_status.dart';

/// In-memory filter state for the Bookings screen.
///
/// `status` is single-select (a booking can only have one status at a time).
/// `hiddenBandIds` is multi-select — bands the user has chosen to hide.
/// Resets on app restart (no persistence). Mirrors `LibraryFilterState`.
class BookingsFilterState {
  const BookingsFilterState({
    this.status = BookingStatus.all,
    this.hiddenBandIds = const {},
  });

  final BookingStatus status;
  final Set<int> hiddenBandIds;

  bool get isActive =>
      status != BookingStatus.all || hiddenBandIds.isNotEmpty;

  /// Count of active constraints — drives the badge on the floating button.
  /// `status != all` counts as 1; each hidden band counts as 1.
  int get activeCount =>
      (status == BookingStatus.all ? 0 : 1) + hiddenBandIds.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookingsFilterState &&
          status == other.status &&
          const SetEquality<int>()
              .equals(hiddenBandIds, other.hiddenBandIds);

  @override
  int get hashCode =>
      Object.hash(status, const SetEquality<int>().hash(hiddenBandIds));

  BookingsFilterState copyWith({
    BookingStatus? status,
    Set<int>? hiddenBandIds,
  }) =>
      BookingsFilterState(
        status: status ?? this.status,
        hiddenBandIds: hiddenBandIds ?? this.hiddenBandIds,
      );
}

class BookingsFilterNotifier extends Notifier<BookingsFilterState> {
  @override
  BookingsFilterState build() => const BookingsFilterState();

  void setStatus(BookingStatus status) {
    state = state.copyWith(status: status);
  }

  void toggleBand(int bandId) {
    final next = Set<int>.from(state.hiddenBandIds);
    if (!next.add(bandId)) next.remove(bandId);
    state = state.copyWith(hiddenBandIds: next);
  }

  void clear() => state = const BookingsFilterState();
}

final bookingsFilterProvider =
    NotifierProvider<BookingsFilterNotifier, BookingsFilterState>(
  BookingsFilterNotifier.new,
);
```

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/features/bookings/providers/bookings_filter_provider_test.dart`
Expected: PASS — all tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/bookings/providers/bookings_filter_provider.dart \
        test/features/bookings/providers/bookings_filter_provider_test.dart
git commit -m "feat(bookings): add bookingsFilterProvider"
```

---

## Task 3: Add `bookingMatchesQuery` helper

**Files:**
- Create: `lib/features/bookings/utils/booking_search.dart`
- Test: `test/features/bookings/utils/booking_search_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/bookings/utils/booking_search_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contact.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';
import 'package:tts_bandmate/features/bookings/utils/booking_search.dart';

BookingSummary _booking({
  String name = 'Acme Wedding',
  String? venueName,
  List<BookingContact> contacts = const [],
}) =>
    BookingSummary(
      id: 1,
      name: name,
      date: '2026-06-01',
      venueName: venueName,
      isPaid: false,
      contacts: contacts,
    );

void main() {
  group('bookingMatchesQuery', () {
    test('empty query matches', () {
      expect(bookingMatchesQuery(_booking(), ''), true);
    });

    test('whitespace-only query matches', () {
      expect(bookingMatchesQuery(_booking(), '   '), true);
    });

    test('matches booking name (case-insensitive)', () {
      expect(bookingMatchesQuery(_booking(name: 'Acme Wedding'), 'acme'),
          true);
      expect(bookingMatchesQuery(_booking(name: 'Acme Wedding'), 'WED'),
          true);
    });

    test('matches venue name', () {
      final b = _booking(venueName: 'The Blue Note');
      expect(bookingMatchesQuery(b, 'blue'), true);
    });

    test('matches contact name', () {
      final b = _booking(contacts: const [
        BookingContact(id: 1, name: 'Alice Johnson'),
      ]);
      expect(bookingMatchesQuery(b, 'johnson'), true);
    });

    test('matches contact email', () {
      final b = _booking(contacts: const [
        BookingContact(id: 1, name: 'Alice', email: 'alice@example.com'),
      ]);
      expect(bookingMatchesQuery(b, 'example.com'), true);
    });

    test('matches contact phone', () {
      final b = _booking(contacts: const [
        BookingContact(id: 1, name: 'Alice', phone: '555-1234'),
      ]);
      expect(bookingMatchesQuery(b, '555'), true);
    });

    test('returns false when nothing matches', () {
      final b = _booking(
        name: 'Acme Wedding',
        venueName: 'The Blue Note',
        contacts: const [BookingContact(id: 1, name: 'Alice')],
      );
      expect(bookingMatchesQuery(b, 'zzzz'), false);
    });

    test('null fields do not throw', () {
      final b = _booking(); // venueName null, contacts empty
      expect(bookingMatchesQuery(b, 'anything'), false);
    });
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/features/bookings/utils/booking_search_test.dart`
Expected: FAIL — `bookingMatchesQuery` not defined.

- [ ] **Step 3: Implement the helper**

```dart
// lib/features/bookings/utils/booking_search.dart
import '../data/models/booking_summary.dart';

/// Returns true if [booking] matches [query] (case-insensitive contains)
/// against any of: name, venue name, or any contact's name/email/phone.
///
/// Empty or whitespace-only queries match everything.
bool bookingMatchesQuery(BookingSummary booking, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;

  if (booking.name.toLowerCase().contains(q)) return true;
  final venue = booking.venueName;
  if (venue != null && venue.toLowerCase().contains(q)) return true;

  for (final c in booking.contacts) {
    if (c.name.toLowerCase().contains(q)) return true;
    final email = c.email;
    if (email != null && email.toLowerCase().contains(q)) return true;
    final phone = c.phone;
    if (phone != null && phone.toLowerCase().contains(q)) return true;
  }
  return false;
}
```

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/features/bookings/utils/booking_search_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/bookings/utils/booking_search.dart \
        test/features/bookings/utils/booking_search_test.dart
git commit -m "feat(bookings): add bookingMatchesQuery helper"
```

---

## Task 4: Add month-strip helpers

**Files:**
- Create: `lib/features/bookings/utils/booking_month_strip.dart`
- Test: `test/features/bookings/utils/booking_month_strip_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/bookings/utils/booking_month_strip_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';
import 'package:tts_bandmate/features/bookings/utils/booking_month_strip.dart';

BookingSummary _b(int id, String date) => BookingSummary(
      id: id,
      name: 'b$id',
      date: date,
      isPaid: false,
      contacts: const [],
    );

void main() {
  group('monthKeyFor', () {
    test('formats year-month with zero-padded month', () {
      expect(monthKeyFor(DateTime(2026, 3, 15)), '2026-03');
      expect(monthKeyFor(DateTime(2026, 12, 1)), '2026-12');
    });
  });

  group('buildMonthKeys', () {
    test('returns empty list for empty input', () {
      expect(buildMonthKeys(const []), isEmpty);
    });

    test('returns sorted unique month keys', () {
      final keys = buildMonthKeys([
        _b(1, '2026-03-10'),
        _b(2, '2026-01-15'),
        _b(3, '2026-03-22'),
        _b(4, '2025-12-01'),
      ]);
      expect(keys, ['2025-12', '2026-01', '2026-03']);
    });

    test('handles multi-year input', () {
      final keys = buildMonthKeys([
        _b(1, '2027-01-01'),
        _b(2, '2025-06-15'),
      ]);
      expect(keys, ['2025-06', '2027-01']);
    });
  });

  group('findNearestUpcomingIndex', () {
    test('returns null for empty list', () {
      expect(findNearestUpcomingIndex(const [], DateTime(2026, 5, 1)),
          isNull);
    });

    test('returns first booking on or after now', () {
      final list = [
        _b(1, '2026-01-01'),
        _b(2, '2026-05-15'),
        _b(3, '2026-08-01'),
      ];
      expect(findNearestUpcomingIndex(list, DateTime(2026, 5, 1)), 1);
    });

    test('treats today (date-only) as upcoming', () {
      final list = [
        _b(1, '2026-04-30'),
        _b(2, '2026-05-01'),
      ];
      expect(findNearestUpcomingIndex(list, DateTime(2026, 5, 1)), 1);
    });

    test('returns last index when all bookings are in the past', () {
      final list = [
        _b(1, '2026-01-01'),
        _b(2, '2026-02-01'),
      ];
      expect(findNearestUpcomingIndex(list, DateTime(2026, 5, 1)), 1);
    });

    test('returns 0 when all bookings are in the future', () {
      final list = [
        _b(1, '2026-06-01'),
        _b(2, '2026-07-01'),
      ];
      expect(findNearestUpcomingIndex(list, DateTime(2026, 5, 1)), 0);
    });

    test('input must already be sorted ascending', () {
      // Documents the contract — caller sorts; helper does not.
      final list = [
        _b(1, '2026-08-01'),
        _b(2, '2026-05-15'),
      ];
      // First element 2026-08-01 is on/after 2026-05-01, so index 0.
      expect(findNearestUpcomingIndex(list, DateTime(2026, 5, 1)), 0);
    });
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/features/bookings/utils/booking_month_strip_test.dart`
Expected: FAIL — helpers not defined.

- [ ] **Step 3: Implement the helpers**

```dart
// lib/features/bookings/utils/booking_month_strip.dart
import '../data/models/booking_summary.dart';

/// Year-month string key for a [DateTime], e.g. `2026-03`. Month is
/// zero-padded so string sort matches chronological sort.
String monthKeyFor(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  return '${d.year}-$m';
}

/// Returns the chronologically-sorted, deduped list of month keys present
/// in [bookings].
///
/// Each entry is a `YYYY-MM` string. Empty input yields an empty list.
List<String> buildMonthKeys(List<BookingSummary> bookings) {
  final set = <String>{};
  for (final b in bookings) {
    set.add(monthKeyFor(b.parsedDate));
  }
  final list = set.toList()..sort();
  return list;
}

/// Returns the index of the first booking in [bookings] whose `parsedDate`
/// is on or after [now]. Falls back to the last index when every booking
/// is in the past. Returns `null` for an empty list.
///
/// **Contract:** [bookings] must already be sorted ascending by date —
/// the helper does not sort.
int? findNearestUpcomingIndex(List<BookingSummary> bookings, DateTime now) {
  if (bookings.isEmpty) return null;
  for (var i = 0; i < bookings.length; i++) {
    if (!bookings[i].parsedDate.isBefore(now)) return i;
  }
  return bookings.length - 1;
}
```

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/features/bookings/utils/booking_month_strip_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/bookings/utils/booking_month_strip.dart \
        test/features/bookings/utils/booking_month_strip_test.dart
git commit -m "feat(bookings): add month-strip helpers"
```

---

## Task 5: Add `BookingsFilterButton` widget

**Files:**
- Create: `lib/features/bookings/widgets/bookings_filter_button.dart`
- Test: `test/features/bookings/widgets/bookings_filter_button_test.dart`

This mirrors `LibraryFilterButton` exactly except it watches `bookingsFilterProvider` instead of `libraryFilterProvider`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/bookings/widgets/bookings_filter_button_test.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_status.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_filter_provider.dart';
import 'package:tts_bandmate/features/bookings/widgets/bookings_filter_button.dart';

void main() {
  testWidgets('renders no badge when no filter is active', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: Center(
              child: BookingsFilterButton(onPressed: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // No badge text rendered.
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('shows badge with active count', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(bookingsFilterProvider.notifier)
        .setStatus(BookingStatus.confirmed);
    container.read(bookingsFilterProvider.notifier).toggleBand(7);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(
            child: BookingsFilterButton(onPressed: () {}),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('invokes onPressed when tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: Center(
              child: BookingsFilterButton(onPressed: () => taps++),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(BookingsFilterButton));
    expect(taps, 1);
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/features/bookings/widgets/bookings_filter_button_test.dart`
Expected: FAIL — `BookingsFilterButton` not defined.

- [ ] **Step 3: Implement the widget**

```dart
// lib/features/bookings/widgets/bookings_filter_button.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/bookings_filter_provider.dart';

/// Floating circular button that opens [BookingsFilterSheet].
///
/// Renders a small red badge with the active-constraint count (status +
/// hidden bands) when any filter is active. Visually mirrors
/// `LibraryFilterButton`.
class BookingsFilterButton extends ConsumerWidget {
  const BookingsFilterButton({
    super.key,
    required this.onPressed,
    this.size = 48,
  });

  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(bookingsFilterProvider);
    final isActive = filter.isActive;
    final count = filter.activeCount;

    final fill = isActive
        ? CupertinoColors.systemBlue.resolveFrom(context)
        : CupertinoColors.tertiarySystemBackground.resolveFrom(context);
    final iconColor = isActive
        ? CupertinoColors.white
        : CupertinoColors.systemBlue.resolveFrom(context);

    return Semantics(
      label: 'Filter bookings',
      hint: isActive ? '$count filters active' : 'No filters active',
      button: true,
      child: SizedBox(
        width: size + 8,
        height: size + 8,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onPressed,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    CupertinoIcons.line_horizontal_3_decrease,
                    color: iconColor,
                    size: 22,
                  ),
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: CupertinoColors.systemBackground
                          .resolveFrom(context),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/features/bookings/widgets/bookings_filter_button_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/bookings/widgets/bookings_filter_button.dart \
        test/features/bookings/widgets/bookings_filter_button_test.dart
git commit -m "feat(bookings): add BookingsFilterButton widget"
```

---

## Task 6: Add `BookingsFilterSheet` widget

**Files:**
- Create: `lib/features/bookings/widgets/bookings_filter_sheet.dart`
- Test: `test/features/bookings/widgets/bookings_filter_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/bookings/widgets/bookings_filter_sheet_test.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_status.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_filter_provider.dart';
import 'package:tts_bandmate/features/bookings/widgets/bookings_filter_sheet.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com', avatarUrl: null);
const _bandA = BandSummary(id: 1, name: 'Band A', isOwner: true);
const _bandB = BandSummary(id: 2, name: 'Band B', isOwner: false);

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._bands);
  final List<BandSummary> _bands;
  @override
  Future<AuthState> build() async =>
      AuthAuthenticated(user: _user, bands: _bands);
}

Widget _harness(ProviderContainer container, List<BandSummary> bands) =>
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: BookingsFilterSheet(bands: bands),
        ),
      ),
    );

ProviderContainer _container(List<BandSummary> bands) {
  final c = ProviderContainer(overrides: [
    authProvider.overrideWith(() => _StubAuthNotifier(bands)),
  ]);
  return c;
}

void main() {
  testWidgets('renders all four status pills and one cell per band',
      (tester) async {
    final container = _container(const [_bandA, _bandB]);
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container, const [_bandA, _bandB]));
    await tester.pump();

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Band A'), findsOneWidget);
    expect(find.text('Band B'), findsOneWidget);
  });

  testWidgets('tapping a status pill updates the provider', (tester) async {
    final container = _container(const [_bandA]);
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container, const [_bandA]));
    await tester.pump();

    expect(container.read(bookingsFilterProvider).status, BookingStatus.all);

    await tester.tap(find.text('Confirmed'));
    await tester.pump();

    expect(container.read(bookingsFilterProvider).status,
        BookingStatus.confirmed);
  });

  testWidgets('tapping a band toggles it in bookingsFilterProvider',
      (tester) async {
    final container = _container(const [_bandA, _bandB]);
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container, const [_bandA, _bandB]));
    await tester.pump();

    expect(container.read(bookingsFilterProvider).hiddenBandIds, isEmpty);

    await tester.tap(find.text('Band A'));
    await tester.pump();

    expect(container.read(bookingsFilterProvider).hiddenBandIds, {1});
  });

  testWidgets('"Clear All" only visible when isActive', (tester) async {
    final container = _container(const [_bandA]);
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container, const [_bandA]));
    await tester.pump();

    expect(find.text('Clear All'), findsNothing);

    container.read(bookingsFilterProvider.notifier).toggleBand(1);
    await tester.pump();

    expect(find.text('Clear All'), findsOneWidget);
  });

  testWidgets('"Clear All" tap resets state', (tester) async {
    final container = _container(const [_bandA]);
    addTearDown(container.dispose);
    container.read(bookingsFilterProvider.notifier)
        .setStatus(BookingStatus.pending);
    container.read(bookingsFilterProvider.notifier).toggleBand(1);

    await tester.pumpWidget(_harness(container, const [_bandA]));
    await tester.pump();

    await tester.tap(find.text('Clear All'));
    await tester.pump();

    final s = container.read(bookingsFilterProvider);
    expect(s.status, BookingStatus.all);
    expect(s.hiddenBandIds, isEmpty);
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/features/bookings/widgets/bookings_filter_sheet_test.dart`
Expected: FAIL — `BookingsFilterSheet` not defined.

- [ ] **Step 3: Implement the widget**

```dart
// lib/features/bookings/widgets/bookings_filter_sheet.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/models/band_summary.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/widgets/band_avatar.dart';
import '../data/models/booking_status.dart';
import '../providers/bookings_filter_provider.dart';

/// Modal popup contents for filtering the Bookings list by status + band.
///
/// Lives inside `showCupertinoModalPopup`. Visually mirrors
/// `LibraryFilterSheet` with an added STATUS section above BANDS.
class BookingsFilterSheet extends ConsumerWidget {
  const BookingsFilterSheet({super.key, required this.bands});

  final List<BandSummary> bands;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(bookingsFilterProvider);
    final notifier = ref.read(bookingsFilterProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.only(bottom: 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _DragHandle(),
            const SizedBox(height: 8),
            _Header(
              isActive: filter.isActive,
              onClear: () {
                HapticFeedback.selectionClick();
                notifier.clear();
              },
            ),
            const SizedBox(height: 8),
            const _SectionLabel(label: 'STATUS'),
            const SizedBox(height: 8),
            _StatusPills(
              current: filter.status,
              onChanged: (s) {
                HapticFeedback.selectionClick();
                notifier.setStatus(s);
              },
            ),
            const SizedBox(height: 12),
            const _SectionLabel(label: 'BANDS'),
            const SizedBox(height: 8),
            _BandsRow(
              bands: bands,
              hiddenBandIds: filter.hiddenBandIds,
              onToggle: (id) {
                HapticFeedback.selectionClick();
                notifier.toggleBand(id);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey4.resolveFrom(context),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isActive, required this.onClear});
  final bool isActive;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Center(
            child: Text(
              'Filter',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          if (isActive)
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onClear,
                child: Text(
                  'Clear All',
                  style: TextStyle(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    fontSize: 15,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}

class _StatusPills extends StatelessWidget {
  const _StatusPills({required this.current, required this.onChanged});

  final BookingStatus current;
  final ValueChanged<BookingStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: BookingStatus.values.map((s) {
          final isSelected = current == s;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? CupertinoColors.systemBlue.resolveFrom(context)
                      : CupertinoColors.tertiarySystemBackground
                          .resolveFrom(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? CupertinoColors.white
                        : CupertinoColors.label.resolveFrom(context),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BandsRow extends ConsumerWidget {
  const _BandsRow({
    required this.bands,
    required this.hiddenBandIds,
    required this.onToggle,
  });

  final List<BandSummary> bands;
  final Set<int> hiddenBandIds;
  final void Function(int bandId) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider).value;
    final user = (auth is AuthAuthenticated) ? auth.user : null;
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: bands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final band = bands[i];
          final isVisible = !hiddenBandIds.contains(band.id);
          final isPersonal = band.isPersonal;
          final avatar = isPersonal
              ? BandAvatar.forUser(
                  imageUrl: user?.avatarUrl,
                  name: user?.name ?? 'You',
                  size: 36,
                )
              : BandAvatar.forBand(band: band, size: 36);
          final label = isPersonal ? 'Personal' : band.name;
          return GestureDetector(
            onTap: () => onToggle(band.id),
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              label: label,
              selected: isVisible,
              button: true,
              child: SizedBox(
                width: 64,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: isVisible ? 1.0 : 0.4,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isVisible
                                ? CupertinoColors.systemBlue
                                    .resolveFrom(context)
                                : CupertinoColors.systemGrey5
                                    .resolveFrom(context),
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: avatar,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Opacity(
                      opacity: isVisible ? 1.0 : 0.4,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/features/bookings/widgets/bookings_filter_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/bookings/widgets/bookings_filter_sheet.dart \
        test/features/bookings/widgets/bookings_filter_sheet_test.dart
git commit -m "feat(bookings): add BookingsFilterSheet widget"
```

---

## Task 7: Add `BookingsBottomBar` widget

**Files:**
- Create: `lib/features/bookings/widgets/bookings_bottom_bar.dart`

This widget has no Riverpod state and no test of its own — it'll be exercised through the screen widget test in Task 11. It mirrors Library's `_BottomSearchBar` exactly.

- [ ] **Step 1: Create the widget**

```dart
// lib/features/bookings/widgets/bookings_bottom_bar.dart
import 'package:flutter/cupertino.dart';

const double bookingsBottomBarHeight = 56.0;

/// Bottom bar with a search field and a circular `+` add button.
/// Mirrors Library's `_BottomSearchBar`.
class BookingsBottomBar extends StatelessWidget {
  const BookingsBottomBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onAdd,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: bookingsBottomBarHeight,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: CupertinoSearchTextField(
              controller: controller,
              onChanged: onChanged,
              placeholder: 'Search',
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            enabled: onAdd != null,
            label: 'Add booking',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onAdd,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: onAdd == null
                      ? CupertinoColors.systemGrey4.resolveFrom(context)
                      : CupertinoColors.activeBlue.resolveFrom(context),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  CupertinoIcons.plus,
                  color: CupertinoColors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it analyzes**

Run: `flutter analyze lib/features/bookings/widgets/bookings_bottom_bar.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/bookings/widgets/bookings_bottom_bar.dart
git commit -m "feat(bookings): add BookingsBottomBar widget"
```

---

## Task 8: Add `BookingsMonthStrip` widget

**Files:**
- Create: `lib/features/bookings/widgets/bookings_month_strip.dart`

This widget owns the pinned-sliver delegate, the horizontal scroller, the chip list, and the keys map. The screen passes in the chronologically-sorted month-key list, the selected key, and tap handlers. The widget exposes a static method to access chip keys for the screen to use with `Scrollable.ensureVisible`.

- [ ] **Step 1: Create the widget**

```dart
// lib/features/bookings/widgets/bookings_month_strip.dart
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

/// Pinned horizontal strip of month chips. The chip whose key matches
/// [selectedKey] is rendered filled; tapping a chip calls [onTap] with
/// that chip's key.
///
/// [chipKeys] is an externally-owned map from month key (`YYYY-MM`) to
/// `GlobalKey`. The screen owns this map so it can call
/// `Scrollable.ensureVisible(chipKeys[key]!.currentContext!, …)` to
/// auto-scroll the strip.
class BookingsMonthStrip extends StatelessWidget {
  const BookingsMonthStrip({
    super.key,
    required this.monthKeys,
    required this.selectedKey,
    required this.onTap,
    required this.chipKeys,
  });

  final List<String> monthKeys;
  final String? selectedKey;
  final ValueChanged<String> onTap;
  final Map<String, GlobalKey> chipKeys;

  static const double height = 52.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: monthKeys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final key = monthKeys[i];
          final isSelected = key == selectedKey;
          final chipKey = chipKeys.putIfAbsent(key, GlobalKey.new);
          return GestureDetector(
            key: chipKey,
            onTap: () => onTap(key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? CupertinoColors.systemBlue.resolveFrom(context)
                    : CupertinoColors.tertiarySystemBackground
                        .resolveFrom(context),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                _label(key),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? CupertinoColors.white
                      : CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Renders `2026-03` as `MAR 26`.
  static String _label(String monthKey) {
    final parts = monthKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final d = DateTime(year, month, 1);
    final mon = DateFormat('MMM').format(d).toUpperCase();
    final yy = (year % 100).toString().padLeft(2, '0');
    return '$mon $yy';
  }
}

/// Pinned [SliverPersistentHeaderDelegate] wrapper for [BookingsMonthStrip].
class BookingsMonthStripDelegate extends SliverPersistentHeaderDelegate {
  BookingsMonthStripDelegate({
    required this.monthKeys,
    required this.selectedKey,
    required this.onTap,
    required this.chipKeys,
  });

  final List<String> monthKeys;
  final String? selectedKey;
  final ValueChanged<String> onTap;
  final Map<String, GlobalKey> chipKeys;

  @override
  double get minExtent => BookingsMonthStrip.height;
  @override
  double get maxExtent => BookingsMonthStrip.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return BookingsMonthStrip(
      monthKeys: monthKeys,
      selectedKey: selectedKey,
      onTap: onTap,
      chipKeys: chipKeys,
    );
  }

  @override
  bool shouldRebuild(BookingsMonthStripDelegate old) =>
      monthKeys != old.monthKeys || selectedKey != old.selectedKey;
}
```

- [ ] **Step 2: Verify it analyzes**

Run: `flutter analyze lib/features/bookings/widgets/bookings_month_strip.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/bookings/widgets/bookings_month_strip.dart
git commit -m "feat(bookings): add BookingsMonthStrip widget"
```

---

## Task 9: Drop `year` from `userBookingsProvider`

**Files:**
- Modify: `lib/features/bookings/providers/bookings_provider.dart`
- Modify: `test/providers/user_bookings_provider_test.dart` (if it exists and exercises `year`)

The repository method `getAllUserBookings` already treats `year` as optional, so dropping it on the provider side is safe — the request just goes out without `?year=…`.

- [ ] **Step 1: Read the existing provider test**

Run: `cat test/providers/user_bookings_provider_test.dart`
Expected: see what shape it asserts on.

- [ ] **Step 2: Update the provider**

Edit `lib/features/bookings/providers/bookings_provider.dart`. Replace the `UserBookingsParams` class and `userBookingsProvider` family with a parameterless `FutureProvider`:

```dart
// Replace this block:
//
// class UserBookingsParams { ... }
// final userBookingsProvider = FutureProvider.family<...>(...)
//
// With:

final userBookingsProvider = FutureProvider<List<BookingSummary>>((ref) {
  final repo = ref.watch(bookingsRepositoryProvider);
  return repo.getAllUserBookings();
});
```

Leave `BandBookingsParams` and `bandBookingsProvider` untouched.

- [ ] **Step 3: Update the existing test (if needed)**

If `test/providers/user_bookings_provider_test.dart` references `UserBookingsParams` or `userBookingsProvider(...)`, update it to call the parameterless `userBookingsProvider`. If the test was specifically about year-passing, replace those assertions with a simpler "fetches all bookings" assertion. Show the working test file before committing.

- [ ] **Step 4: Run the test**

Run: `flutter test test/providers/user_bookings_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full test suite to find other callers**

Run: `flutter test`
Expected: any failures highlight call sites in `bookings_screen.dart` and `bookings_screen_multi_band_test.dart` that still pass `UserBookingsParams`. Note them — they're addressed in Tasks 10–11.

- [ ] **Step 6: Commit**

```bash
git add lib/features/bookings/providers/bookings_provider.dart \
        test/providers/user_bookings_provider_test.dart
git commit -m "refactor(bookings): drop year param from userBookingsProvider"
```

---

## Task 10: Rewrite the Bookings screen

**Files:**
- Modify: `lib/features/bookings/screens/bookings_screen.dart` (full rewrite of body; deletes `_StickyControls`, `_FilterPills`, `_YearStepper`, `_BookingsFilter`)

This is the largest task; one big edit because the screen's structure changes substantially.

- [ ] **Step 1: Replace the file contents**

Replace the entire contents of `lib/features/bookings/screens/bookings_screen.dart` with:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';
import 'package:tts_bandmate/shared/widgets/band_identity_chip.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import 'package:tts_bandmate/shared/widgets/status_chip.dart';

import '../data/models/booking_status.dart';
import '../data/models/booking_summary.dart';
import '../providers/bookings_filter_provider.dart';
import '../providers/bookings_provider.dart';
import '../utils/booking_month_strip.dart';
import '../utils/booking_search.dart';
import '../widgets/bookings_bottom_bar.dart';
import '../widgets/bookings_filter_button.dart';
import '../widgets/bookings_filter_sheet.dart';
import '../widgets/bookings_month_strip.dart';
import '../widgets/create_booking_sheet.dart';

// ── List item discriminated union ─────────────────────────────────────────────

sealed class _ListItem {}

final class _HeaderItem extends _ListItem {
  _HeaderItem(this.label, this.monthKey);
  final String label;     // e.g. "March 2026"
  final String monthKey;  // e.g. "2026-03"
}

final class _CardItem extends _ListItem {
  _CardItem(this.booking);
  final BookingSummary booking;
}

// ── Root screen ───────────────────────────────────────────────────────────────

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _query = '';

  String? _selectedMonthKey;
  String? _lastJumpedFingerprint;

  // Keys for vertical month-header widgets and horizontal chip widgets.
  // Owned by the screen so we can call Scrollable.ensureVisible on them.
  final Map<String, GlobalKey> _headerKeys = {};
  final Map<String, GlobalKey> _chipKeys = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onVerticalScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onVerticalScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Search ──────────────────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    setState(() => _query = value);
  }

  // ── Add flow ────────────────────────────────────────────────────────────────

  Future<void> _onNewBooking() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) {
        return CreateBookingSheet(
          onBandSelected: (bandId) {
            Navigator.of(sheetContext).pop();
            context.push('/bookings/$bandId/new');
          },
        );
      },
    );
  }

  // ── Filter sheet ────────────────────────────────────────────────────────────

  void _openFilterSheet() {
    final auth = ref.read(authProvider).value;
    final bands = (auth is AuthAuthenticated) ? auth.bands : <BandSummary>[];
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => BookingsFilterSheet(bands: bands),
    );
  }

  // ── Month strip / scrolling ─────────────────────────────────────────────────

  void _onMonthChipTap(String monthKey) {
    setState(() => _selectedMonthKey = monthKey);
    final headerKey = _headerKeys[monthKey];
    final ctx = headerKey?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// On vertical scroll, find the topmost visible `_HeaderItem` and update
  /// `_selectedMonthKey` if it changed. Frame-aligned to avoid jank.
  void _onVerticalScroll() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final topKey = _findTopVisibleMonthKey();
      if (topKey != null && topKey != _selectedMonthKey) {
        setState(() => _selectedMonthKey = topKey);
        // Keep the chip visible.
        final chipCtx = _chipKeys[topKey]?.currentContext;
        if (chipCtx != null) {
          Scrollable.ensureVisible(
            chipCtx,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  /// Returns the month key of the topmost rendered `_HeaderItem` whose
  /// vertical position is below the strip. If none is currently below the
  /// strip, returns the key of the last header above it (so the chip stays
  /// "stuck" on the month the user is scrolled into).
  String? _findTopVisibleMonthKey() {
    // Threshold: anything whose top edge is within the visible viewport
    // and at-or-below the strip counts as "in view".
    const stripBottom = BookingsMonthStrip.height + 8;
    String? lastAbove;
    for (final entry in _headerKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy >= stripBottom) {
        return lastAbove ?? entry.key;
      }
      lastAbove = entry.key;
    }
    return lastAbove;
  }

  /// On a fresh data payload, set `_selectedMonthKey` to the month
  /// containing the nearest-upcoming booking and scroll to it.
  void _maybeJumpToNearest(List<BookingSummary> sortedFiltered) {
    final fingerprint = _fingerprint(sortedFiltered);
    if (fingerprint == _lastJumpedFingerprint) return;
    _lastJumpedFingerprint = fingerprint;

    final idx = findNearestUpcomingIndex(sortedFiltered, DateTime.now());
    if (idx == null) {
      _selectedMonthKey = null;
      return;
    }
    final target = monthKeyFor(sortedFiltered[idx].parsedDate);
    _selectedMonthKey = target;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final headerCtx = _headerKeys[target]?.currentContext;
      if (headerCtx != null) {
        Scrollable.ensureVisible(
          headerCtx,
          alignment: 0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
      final chipCtx = _chipKeys[target]?.currentContext;
      if (chipCtx != null) {
        Scrollable.ensureVisible(
          chipCtx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Stable fingerprint for the booking list — used to dedupe initial
  /// scroll jumps across rebuilds.
  String _fingerprint(List<BookingSummary> bookings) {
    if (bookings.isEmpty) return 'empty';
    final ids = bookings.map((b) => b.id).join(',');
    return ids;
  }

  // ── List building ───────────────────────────────────────────────────────────

  /// Returns `(visibleAfterFilter, items, monthKeys)`.
  ///   - visibleAfterFilter: filtered by status + hidden bands; sorted asc
  ///     by date. Used for "jump to nearest" and the month strip.
  ///   - items: visible-after-search list interleaved with month headers.
  ///     Used to render the SliverList.
  ///   - monthKeys: chronological unique keys from visibleAfterFilter
  ///     (NOT the search-narrowed list — strip stays stable while typing).
  ({
    List<BookingSummary> visibleAfterFilter,
    List<_ListItem> items,
    List<String> monthKeys,
  }) _buildListData(
    List<BookingSummary> all,
    BookingsFilterState filter,
    String query,
  ) {
    final sorted = [...all]
      ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));

    final afterFilter = sorted.where((b) {
      if (filter.status != BookingStatus.all) {
        if ((b.status?.toLowerCase()) != filter.status.apiKey) return false;
      }
      final bandId = b.band?.id;
      if (bandId != null && filter.hiddenBandIds.contains(bandId)) {
        return false;
      }
      return true;
    }).toList();

    final monthKeys = buildMonthKeys(afterFilter);

    final searched = query.trim().isEmpty
        ? afterFilter
        : afterFilter.where((b) => bookingMatchesQuery(b, query)).toList();

    final items = <_ListItem>[];
    String? lastMonthKey;
    for (final booking in searched) {
      final mk = monthKeyFor(booking.parsedDate);
      if (mk != lastMonthKey) {
        items.add(_HeaderItem(
          DateFormat('MMMM yyyy').format(booking.parsedDate),
          mk,
        ));
        lastMonthKey = mk;
      }
      items.add(_CardItem(booking));
    }
    return (
      visibleAfterFilter: afterFilter,
      items: items,
      monthKeys: monthKeys,
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(userBookingsProvider);
    final filter = ref.watch(bookingsFilterProvider);

    return CupertinoPageScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;
          return Center(
            child: SizedBox(
              width: maxWidth,
              child: Column(
                children: [
                  Expanded(
                    child: bookingsAsync.when(
                      loading: () => CustomScrollView(
                        slivers: const [
                          CupertinoSliverNavigationBar(
                            largeTitle: Text('Bookings'),
                          ),
                          SliverFillRemaining(
                            child:
                                Center(child: CupertinoActivityIndicator()),
                          ),
                        ],
                      ),
                      error: (e, _) => CustomScrollView(
                        slivers: [
                          const CupertinoSliverNavigationBar(
                            largeTitle: Text('Bookings'),
                          ),
                          SliverFillRemaining(
                            child: ErrorView(
                              message: ErrorView.friendlyMessage(e),
                              onRetry: () =>
                                  ref.invalidate(userBookingsProvider),
                            ),
                          ),
                        ],
                      ),
                      data: (bookings) {
                        final data =
                            _buildListData(bookings, filter, _query);

                        // Jump-on-load uses the filtered list (not search).
                        _maybeJumpToNearest(data.visibleAfterFilter);

                        // Refresh keys: drop stale ones, keep current.
                        _headerKeys.removeWhere(
                            (k, _) => !data.monthKeys.contains(k));
                        for (final k in data.monthKeys) {
                          _headerKeys.putIfAbsent(k, GlobalKey.new);
                        }

                        return _buildContent(context, ref, data, filter);
                      },
                    ),
                  ),
                  BookingsBottomBar(
                    controller: _searchController,
                    onChanged: _onQueryChanged,
                    onAdd: _onNewBooking,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ({
      List<BookingSummary> visibleAfterFilter,
      List<_ListItem> items,
      List<String> monthKeys,
    }) data,
    BookingsFilterState filter,
  ) {
    // All bookings hidden by filter → dedicated empty state.
    if (data.visibleAfterFilter.isEmpty && filter.isActive) {
      return Stack(
        children: [
          CustomScrollView(
            slivers: [
              const CupertinoSliverNavigationBar(
                largeTitle: Text('Bookings'),
              ),
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.eye_slash,
                        size: 48,
                        color: CupertinoColors.secondaryLabel
                            .resolveFrom(context),
                      ),
                      const SizedBox(height: 12),
                      const Text('No bookings match your filters'),
                      const SizedBox(height: 12),
                      CupertinoButton(
                        onPressed: () => ref
                            .read(bookingsFilterProvider.notifier)
                            .clear(),
                        child: const Text('Show all'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _filterButtonOverlay(context),
        ],
      );
    }

    // No bookings at all (after filter).
    if (data.visibleAfterFilter.isEmpty) {
      return Stack(
        children: [
          CustomScrollView(
            slivers: [
              CupertinoSliverRefreshControl(
                onRefresh: () async =>
                    ref.invalidate(userBookingsProvider),
              ),
              const CupertinoSliverNavigationBar(
                largeTitle: Text('Bookings'),
              ),
              const SliverFillRemaining(
                child: EmptyStateView(
                  icon: CupertinoIcons.calendar_badge_minus,
                  title: 'No bookings yet',
                  subtitle: 'Tap + below to add one.',
                ),
              ),
            ],
          ),
          _filterButtonOverlay(context),
        ],
      );
    }

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            CupertinoSliverRefreshControl(
              onRefresh: () async =>
                  ref.invalidate(userBookingsProvider),
            ),
            const CupertinoSliverNavigationBar(
              largeTitle: Text('Bookings'),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: BookingsMonthStripDelegate(
                monthKeys: data.monthKeys,
                selectedKey: _selectedMonthKey,
                onTap: _onMonthChipTap,
                chipKeys: _chipKeys,
              ),
            ),
            if (data.items.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'No matching bookings',
                    style: TextStyle(
                        color: CupertinoColors.secondaryLabel),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = data.items[index];
                    return switch (item) {
                      _HeaderItem(:final label, :final monthKey) =>
                        _MonthHeader(
                          key: _headerKeys[monthKey],
                          label: label,
                        ),
                      _CardItem(:final booking) => _BookingCard(
                          booking: booking,
                          onTap: () {
                            final bandId = booking.band?.id;
                            if (bandId != null) {
                              context.push(
                                '/bookings/$bandId/${booking.id}',
                              );
                            }
                          },
                        ),
                    };
                  },
                  childCount: data.items.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
        _filterButtonOverlay(context),
      ],
    );
  }

  Widget _filterButtonOverlay(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top + 50;
    return Positioned(
      top: topInset,
      right: 12,
      child: BookingsFilterButton(onPressed: _openFilterSheet),
    );
  }
}

// ── Month header ──────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Booking card ──────────────────────────────────────────────────────────────

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, this.onTap});

  final BookingSummary booking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColor(context, booking.status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              booking.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (booking.status != null)
                            StatusChip(status: booking.status!),
                        ],
                      ),
                      if (booking.band != null) ...[
                        const SizedBox(height: 4),
                        BandIdentityChip(band: booking.band!),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(booking),
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                      ),
                      if (booking.venueName != null &&
                          booking.venueName!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.location,
                              size: 11,
                              color: CupertinoColors.tertiaryLabel
                                  .resolveFrom(context),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                booking.venueName!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.secondaryLabel
                                      .resolveFrom(context),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        booking.displayPrice,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.systemBlue
                              .resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(BookingSummary booking) {
    final dateStr =
        DateFormat('EEE, MMM d, yyyy').format(booking.parsedDate);
    if (booking.startTime != null && booking.startTime!.isNotEmpty) {
      return '$dateStr at ${toAmPm(booking.startTime!)}';
    }
    return dateStr;
  }

  Color _accentColor(BuildContext context, String? status) =>
      switch (status?.toLowerCase()) {
        'confirmed' => CupertinoColors.systemGreen.resolveFrom(context),
        'pending' => CupertinoColors.systemOrange.resolveFrom(context),
        'draft' => CupertinoColors.systemBlue.resolveFrom(context),
        'cancelled' || 'canceled' =>
          CupertinoColors.systemRed.resolveFrom(context),
        _ => CupertinoColors.systemFill.resolveFrom(context),
      };
}
```

- [ ] **Step 2: Run `flutter analyze` on the file**

Run: `flutter analyze lib/features/bookings/screens/bookings_screen.dart`
Expected: `No issues found!`. Fix any analyzer complaints inline.

- [ ] **Step 3: Run the full analyzer**

Run: `flutter analyze`
Expected: `No issues found!` across the project. The screen rewrite removed the only references to `UserBookingsParams`, `_BookingsFilter`, `_StickyControls`, `_FilterPills`, `_YearStepper`.

- [ ] **Step 4: Commit**

```bash
git add lib/features/bookings/screens/bookings_screen.dart
git commit -m "feat(bookings): rewrite screen with bottom search + month strip"
```

---

## Task 11: Update the existing bookings screen widget test

**Files:**
- Modify: `test/features/bookings/bookings_screen_multi_band_test.dart`

The existing test was written against the old `_BookingsFilter` enum and year stepper. Update it to assert on the new shape.

- [ ] **Step 1: Read the existing test**

Run: `cat test/features/bookings/bookings_screen_multi_band_test.dart`
Expected: see what behavior it asserts.

- [ ] **Step 2: Adapt the test**

Update the test to reflect the new screen shape:
- Replace assertions about year stepper / status pill row with assertions about the bottom bar (search field present, "Add booking" button present) and the floating filter button.
- If the test was about multi-band card rendering, that behavior is preserved — just confirm the cards still render with their `BandIdentityChip`.

If a previous assertion no longer applies (e.g., "year stepper increments year"), delete it. If a previous assertion would still pass on the new screen (e.g., "renders three booking cards with names X, Y, Z"), keep it.

Show the rewritten test before running.

- [ ] **Step 3: Run the test**

Run: `flutter test test/features/bookings/bookings_screen_multi_band_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add test/features/bookings/bookings_screen_multi_band_test.dart
git commit -m "test(bookings): update screen test for new layout"
```

---

## Task 12: Fix Library filter button position

**Files:**
- Modify: `lib/features/library/screens/library_screen.dart`

Currently the floating filter button is positioned at `top: _kFilterButtonTopInset = 8.0` from the screen top, which puts it under the system status bar / battery icon. Change to be below the nav bar.

- [ ] **Step 1: Read the relevant block**

Run: `grep -n "_kFilterButtonTopInset\|_filterButtonOverlay" lib/features/library/screens/library_screen.dart`
Expected: shows the constant declaration and the `_filterButtonOverlay` getter.

- [ ] **Step 2: Update the positioning**

In `lib/features/library/screens/library_screen.dart`:

Remove the line:
```dart
const double _kFilterButtonTopInset = 8.0;
```

Replace the `_filterButtonOverlay` getter:
```dart
  Widget _filterButtonOverlay() => Positioned(
        top: _kFilterButtonTopInset,
        right: _kIndexWidth + 4,
        child: LibraryFilterButton(onPressed: _openFilterSheet),
      );
```

With:
```dart
  Widget _filterButtonOverlay(BuildContext context) => Positioned(
        top: MediaQuery.of(context).padding.top + 50,
        right: _kIndexWidth + 4,
        child: LibraryFilterButton(onPressed: _openFilterSheet),
      );
```

Then update each call site of `_filterButtonOverlay()` in the same file to pass `context`: `_filterButtonOverlay(context)`.

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze lib/features/library/screens/library_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run the existing Library tests**

Run: `flutter test test/features/library/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/library/screens/library_screen.dart
git commit -m "fix(library): anchor floating filter button below nav bar"
```

---

## Task 13: Final verification

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: PASS — every test in the project still green.

- [ ] **Step 2: Run the analyzer over the project**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Smoke-test the app**

Run: `flutter run -d linux` (or `chrome`)
Click the Bookings tab. Verify by hand:
- Bottom bar with search field + circular `+` is present.
- Floating filter button is below the nav bar (not under the status bar).
- Tapping the filter button opens the sheet with STATUS + BANDS sections.
- Tapping a status pill in the sheet filters the list.
- Tapping a band hides its bookings.
- Pinned month strip is present below the nav bar; chips show month + year.
- On load, the list scrolls to the nearest upcoming booking and the matching chip is highlighted.
- Tapping a chip jumps the vertical list to that month.
- Scrolling the vertical list updates the highlighted chip.
- Typing in the search field live-filters by booking name, venue, contact name/email/phone.
- Tapping `+` in the bottom bar opens the existing `CreateBookingSheet`.
- Open Library and confirm the floating filter button is no longer under the status bar.

- [ ] **Step 4: No commit needed for this task** — already covered by previous commits.

---

## Self-review notes (for the engineer reading this)

- **Spec coverage:** every spec section has a task. Status enum (Task 1), filter provider (Task 2), search helper (Task 3), month-strip helpers (Task 4), filter button (Task 5), filter sheet (Task 6), bottom bar (Task 7), month strip widget (Task 8), provider rewrite (Task 9), screen rewrite (Task 10), existing test update (Task 11), Library button fix (Task 12), final verification (Task 13).
- **Type consistency:** `BookingStatus.apiKey` returns the lowercase string used to match `BookingSummary.status`. `monthKeyFor` and `buildMonthKeys` use `YYYY-MM` strings everywhere. `_HeaderItem` carries `monthKey: String` (the new shape) — different from the old `monthIndex: int`.
- **Backend verification:** the spec calls out that we need to verify `GET /api/mobile/me/bookings` works without the `year` query param. The repository's `getAllUserBookings` already treats `year` as optional and just skips it when null, so the request will go out without `?year=…`. The Laravel side should accept this; if it 422s during smoke-test, fall back by calling the endpoint with the current year as a sentinel and updating the spec/plan accordingly.
