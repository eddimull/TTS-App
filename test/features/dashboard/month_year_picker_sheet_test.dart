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
    await tester.drag(find.text(monthLabel), const Offset(0, -2.2 * itemExtent));
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
