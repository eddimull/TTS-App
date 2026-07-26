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
