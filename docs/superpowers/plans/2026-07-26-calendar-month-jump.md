# Dashboard Calendar Month/Year Jump Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping the dashboard calendar's month/year header opens a Cupertino sheet with a month/year wheel picker plus Cancel/Today/Done, and jumps the calendar to the chosen month.

**Architecture:** `TableCalendar` (v3.2.0) already exposes `onHeaderTapped`; thread a callback from `_CalendarSection` → `_DashboardContent` → `_DashboardScreenState` (same pattern as `onPageChanged`). A new self-contained `MonthYearPickerSheet` widget returns the chosen month via `Navigator.pop`; the screen applies it exactly like a swipe (set `_focusedDay`, clear `_selectedDay`, `ensureMonthLoaded`).

**Tech Stack:** Flutter/Cupertino, `table_calendar` 3.2.0, `CupertinoDatePicker` in `monthYear` mode, Riverpod v2, `flutter_test` widget tests.

**Spec:** `docs/superpowers/specs/2026-07-26-calendar-month-jump-design.md`

## Global Constraints

- Cupertino widgets only; sheet background must be `CupertinoColors.systemBackground.resolveFrom(context)` — never raw label colors (dark-mode rule).
- Picker bounds mirror the calendar's: `now - 365 days` … `now + 5 years` (`dashboard_screen.dart` `_CalendarSection` `firstDay`/`lastDay`).
- `CupertinoDatePicker` **asserts** `initialDateTime` is within `minimumDate..maximumDate` — always clamp before constructing it.
- `TableCalendar` requires `focusedDay` within `firstDay..lastDay` — clamp the jump target in the screen handler too (first-of-month of the oldest pickable month precedes `firstDay`).
- No time-bomb dates in tests: compute every date relative to `DateTime.now()`; never hardcode a calendar date.
- Run `flutter analyze` before each commit; it must be clean.

---

### Task 1: `MonthYearPickerSheet` widget

**Files:**
- Create: `lib/features/dashboard/widgets/month_year_picker_sheet.dart`
- Test: `test/features/dashboard/month_year_picker_sheet_test.dart`

**Interfaces:**
- Consumes: nothing project-specific (pure Cupertino widget).
- Produces: `MonthYearPickerSheet.show(BuildContext context, {required DateTime focusedDay, required DateTime now}) → Future<DateTime?>` — resolves with the picked month (**first-of-month** `DateTime`), the current date (`DateTime.now()`) for **Today**, or `null` for Cancel/dismiss. Task 2 calls exactly this.

- [ ] **Step 1: Write the failing tests**

Create `test/features/dashboard/month_year_picker_sheet_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/features/dashboard/widgets/month_year_picker_sheet.dart';

void main() {
  // CupertinoPicker item extent used by CupertinoDatePicker — dragging by
  // one multiple of this advances the wheel one notch.
  const itemExtent = 32.0;

  DateTime? result;
  var completed = false;

  Widget host({required DateTime focusedDay, required DateTime now}) {
    result = null;
    completed = false;
    return CupertinoApp(
      home: Builder(
        builder: (context) => CupertinoButton(
          onPressed: () async {
            result = await MonthYearPickerSheet.show(
              context,
              focusedDay: focusedDay,
              now: now,
            );
            completed = true;
          },
          child: const Text('open'),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester,
      {required DateTime focusedDay, required DateTime now}) async {
    await tester.pumpWidget(host(focusedDay: focusedDay, now: now));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Done returns the month picked on the wheel', (tester) async {
    final now = DateTime.now();
    await open(tester, focusedDay: now, now: now);

    // Advance the month wheel two notches (drag the visible month name up).
    final monthLabel = DateFormat.MMMM().format(DateTime(now.year, now.month));
    await tester.drag(find.text(monthLabel), const Offset(0, -2 * itemExtent));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final expected = DateTime(now.year, now.month + 2);
    expect(completed, isTrue);
    expect(result, isNotNull);
    expect(result!.year, expected.year);
    expect(result!.month, expected.month);
    expect(result!.day, 1, reason: 'Done must return a first-of-month value');
  });

  testWidgets('Today returns the current date even when opened on another month',
      (tester) async {
    final now = DateTime.now();
    final future = DateTime(now.year, now.month + 6);
    await open(tester, focusedDay: future, now: now);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result, isNotNull);
    expect(result!.year, now.year);
    expect(result!.month, now.month);
  });

  testWidgets('Cancel returns null', (tester) async {
    final now = DateTime.now();
    await open(tester, focusedDay: now, now: now);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('out-of-bounds focusedDay is clamped instead of asserting',
      (tester) async {
    final now = DateTime.now();
    // Two years back — before the one-year minimum. Without clamping,
    // CupertinoDatePicker asserts "initial date is not greater than or
    // equal to minimumDate" and the sheet never opens.
    final farPast = DateTime(now.year - 2, now.month);
    await open(tester, focusedDay: farPast, now: now);

    // Sheet opened successfully and shows the minimum (clamped) month.
    expect(find.byType(MonthYearPickerSheet), findsOneWidget);
    final minMonth = DateTime(now.year - 1, now.month);
    expect(find.text(DateFormat.MMMM().format(minMonth)), findsWidgets);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result!.year, minMonth.year);
    expect(result!.month, minMonth.month);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/dashboard/month_year_picker_sheet_test.dart`
Expected: FAIL — `month_year_picker_sheet.dart` does not exist (compile error).

- [ ] **Step 3: Implement the widget**

Create `lib/features/dashboard/widgets/month_year_picker_sheet.dart`:

```dart
import 'package:flutter/cupertino.dart';

/// Modal popup contents for jumping the dashboard calendar to a month/year.
///
/// Lives inside `showCupertinoModalPopup<DateTime>` — pops with the picked
/// month (Done, first-of-month), the current date (Today), or null
/// (Cancel / tapped-away).
class MonthYearPickerSheet extends StatefulWidget {
  const MonthYearPickerSheet({
    super.key,
    required this.initialMonth,
    required this.minimumMonth,
    required this.maximumMonth,
  });

  /// First-of-month values; [initialMonth] must lie within the bounds
  /// (callers go through [show], which clamps).
  final DateTime initialMonth;
  final DateTime minimumMonth;
  final DateTime maximumMonth;

  /// Shows the sheet for [focusedDay] and resolves with the chosen month.
  ///
  /// Bounds mirror the dashboard calendar's range (one year back, five years
  /// forward of [now]), normalised to first-of-month so the picker's
  /// initial-value assertions can't trip on partial months.
  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime focusedDay,
    required DateTime now,
  }) {
    final min = DateTime(now.year - 1, now.month);
    final max = DateTime(now.year + 5, now.month);
    var initial = DateTime(focusedDay.year, focusedDay.month);
    if (initial.isBefore(min)) initial = min;
    if (initial.isAfter(max)) initial = max;
    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (_) => MonthYearPickerSheet(
        initialMonth: initial,
        minimumMonth: min,
        maximumMonth: max,
      ),
    );
  }

  @override
  State<MonthYearPickerSheet> createState() => _MonthYearPickerSheetState();
}

class _MonthYearPickerSheetState extends State<MonthYearPickerSheet> {
  late DateTime _selected = widget.initialMonth;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.of(context).pop(DateTime.now()),
                  child: const Text('Today'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 216,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.monthYear,
                initialDateTime: widget.initialMonth,
                minimumDate: widget.minimumMonth,
                maximumDate: widget.maximumMonth,
                onDateTimeChanged: (value) => _selected = value,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/dashboard/month_year_picker_sheet_test.dart`
Expected: 4 tests PASS. If the "Done returns the month picked" test lands one notch off, adjust only the drag distance multiplier in the test (wheel physics), never the widget.

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze`
Expected: No issues found.

```bash
git add lib/features/dashboard/widgets/month_year_picker_sheet.dart test/features/dashboard/month_year_picker_sheet_test.dart
git commit -m "feat(dashboard): add month/year picker sheet widget"
```

---

### Task 2: Wire the calendar header tap to the sheet

**Files:**
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart`
  - `_DashboardScreenState` (~line 35): add `_openMonthYearPicker` / `_jumpToMonth`, pass `onHeaderTapped` where `_DashboardContent` is constructed (~line 168)
  - `_DashboardContent` (~line 225): new `onHeaderTapped` field, thread to `_CalendarSection` (~line 323)
  - `_CalendarSection` (~line 388): new `onHeaderTapped` field, pass to `TableCalendar`
- Test: `test/features/dashboard/dashboard_month_jump_test.dart`

**Interfaces:**
- Consumes: `MonthYearPickerSheet.show(context, focusedDay: DateTime, now: DateTime) → Future<DateTime?>` (Task 1); `TableCalendar.onHeaderTapped: void Function(DateTime focusedDay)` (table_calendar 3.2.0); `DashboardNotifier.ensureMonthLoaded(DateTime)` (existing).
- Produces: nothing consumed by later tasks (final task).

- [ ] **Step 1: Write the failing test**

Create `test/features/dashboard/dashboard_month_jump_test.dart`. The harness (fixed auth, stub band, fake repository) copies the pattern from `test/features/dashboard/dashboard_resume_recover_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons, Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';
import 'package:tts_bandmate/features/dashboard/data/models/upcoming_chart.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/dashboard/screens/dashboard_screen.dart';
import 'package:tts_bandmate/features/dashboard/widgets/month_year_picker_sheet.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

final _throwingDio = Dio();
const _itemExtent = 32.0;

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override
  Future<AuthState> build() async => _fixed;
}

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeDashboardRepository extends DashboardRepository {
  _FakeDashboardRepository() : super(_throwingDio);

  final List<(String, String)> requestedNewerWindows = [];

  @override
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard({String? to}) async =>
          (events: const <EventSummary>[], upcomingCharts: const <UpcomingChart>[]);

  @override
  Future<List<EventSummary>> loadOlderEvents(String beforeDate) async => const [];

  @override
  Future<List<EventSummary>> loadNewerEvents(
      String afterDate, String beforeDate) async {
    requestedNewerWindows.add((afterDate, beforeDate));
    return const [];
  }
}

void main() {
  const band = BandSummary(id: 1, name: 'Alpha', isOwner: true);

  Widget host(_FakeDashboardRepository repo) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(
              const AuthAuthenticated(
                user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
                bands: [band],
              ),
            )),
        selectedBandProvider.overrideWith(() => _StubBand()),
        dashboardRepositoryProvider.overrideWithValue(repo),
      ],
      child: const CupertinoApp(home: Material(child: DashboardScreen())),
    );
  }

  String headerTitle(DateTime month) => DateFormat.yMMMM().format(month);

  Future<void> pumpDashboard(WidgetTester tester,
      _FakeDashboardRepository repo) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping the calendar header opens the month/year picker sheet',
      (tester) async {
    final repo = _FakeDashboardRepository();
    await pumpDashboard(tester, repo);

    await tester.tap(find.text(headerTitle(DateTime.now())));
    await tester.pumpAndSettle();

    expect(find.byType(MonthYearPickerSheet), findsOneWidget);
  });

  testWidgets(
      'picking a distant month jumps the calendar and triggers a month load',
      (tester) async {
    final repo = _FakeDashboardRepository();
    await pumpDashboard(tester, repo);
    final now = DateTime.now();

    await tester.tap(find.text(headerTitle(now)));
    await tester.pumpAndSettle();

    // Advance the wheel 5 months — safely beyond the ~90-day initial
    // forward window regardless of today's day-of-month.
    final monthLabel = DateFormat.MMMM().format(DateTime(now.year, now.month));
    await tester.drag(find.text(monthLabel), const Offset(0, -5 * _itemExtent));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final target = DateTime(now.year, now.month + 5);
    expect(find.text(headerTitle(target)), findsOneWidget,
        reason: 'calendar header must now show the picked month');
    expect(repo.requestedNewerWindows, isNotEmpty,
        reason: 'jumping past the loaded window must trigger '
            'ensureMonthLoaded, same as swiping there');
  });

  testWidgets('Today resets the calendar to the current month', (tester) async {
    final repo = _FakeDashboardRepository();
    await pumpDashboard(tester, repo);
    final now = DateTime.now();

    // Park the calendar 4 months ahead via the header chevron first.
    final nextChevron = find.byIcon(Icons.chevron_right);
    for (var i = 0; i < 4; i++) {
      await tester.tap(nextChevron);
      await tester.pumpAndSettle();
    }
    final parked = DateTime(now.year, now.month + 4);
    expect(find.text(headerTitle(parked)), findsOneWidget);

    await tester.tap(find.text(headerTitle(parked)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    expect(find.text(headerTitle(now)), findsOneWidget,
        reason: 'Today must park the calendar back on the current month');
    expect(find.byType(MonthYearPickerSheet), findsNothing);
  });

  testWidgets('Cancel leaves the focused month untouched', (tester) async {
    final repo = _FakeDashboardRepository();
    await pumpDashboard(tester, repo);
    final now = DateTime.now();

    await tester.tap(find.text(headerTitle(now)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text(headerTitle(now)), findsOneWidget);
    expect(find.byType(MonthYearPickerSheet), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/dashboard/dashboard_month_jump_test.dart`
Expected: FAIL — first test: tapping the header does nothing, `MonthYearPickerSheet` never appears (`findsOneWidget` fails with zero found).

- [ ] **Step 3: Wire the callback through the three layers**

All edits in `lib/features/dashboard/screens/dashboard_screen.dart`.

**3a — import** (top of file, alongside the other widget imports):

```dart
import '../widgets/month_year_picker_sheet.dart';
```

**3b — `_DashboardScreenState`:** add the two methods (next to `_openFilterSheet`, ~line 212):

```dart
Future<void> _openMonthYearPicker() async {
  final picked = await MonthYearPickerSheet.show(
    context,
    focusedDay: _focusedDay,
    now: DateTime.now(),
  );
  if (picked == null || !mounted) return;
  _jumpToMonth(picked);
}

void _jumpToMonth(DateTime month) {
  // Keep the target inside TableCalendar's firstDay..lastDay — the
  // first-of-month of the oldest pickable month precedes firstDay.
  final now = DateTime.now();
  final firstAllowed = now.subtract(const Duration(days: 365));
  final lastAllowed = now.add(const Duration(days: 365 * 5));
  var target = month;
  if (target.isBefore(firstAllowed)) target = firstAllowed;
  if (target.isAfter(lastAllowed)) target = lastAllowed;
  setState(() {
    _focusedDay = target;
    _selectedDay = null;
  });
  unawaited(
    ref.read(dashboardProvider.notifier).ensureMonthLoaded(target),
  );
}
```

**3c — `_DashboardContent` construction** (in the `data:` branch, after the `onPageChanged:` argument ~line 194):

```dart
onHeaderTapped: (_) => _openMonthYearPicker(),
```

**3d — `_DashboardContent` widget** (~line 225): add the field and constructor param alongside `onPageChanged`:

```dart
required this.onHeaderTapped,
```

```dart
final void Function(DateTime focusedDay) onHeaderTapped;
```

and pass it where `_CalendarSection` is built (~line 323):

```dart
onHeaderTapped: widget.onHeaderTapped,
```

**3e — `_CalendarSection`** (~line 388): add the field and constructor param alongside `onPageChanged`:

```dart
this.onHeaderTapped,
```

```dart
final void Function(DateTime focusedDay)? onHeaderTapped;
```

and pass it to `TableCalendar` (after `onPageChanged:` ~line 421):

```dart
onHeaderTapped: onHeaderTapped,
```

- [ ] **Step 4: Run the new tests, then the full suite**

Run: `flutter test test/features/dashboard/dashboard_month_jump_test.dart`
Expected: 4 tests PASS.

Run: `flutter test`
Expected: all tests PASS (the resume-recover and calendar-filter integration tests drive the same screen — they must stay green).

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze`
Expected: No issues found.

```bash
git add lib/features/dashboard/screens/dashboard_screen.dart test/features/dashboard/dashboard_month_jump_test.dart
git commit -m "feat(dashboard): tap calendar header to jump to a month or reset to today"
```
