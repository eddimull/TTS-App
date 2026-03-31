import 'package:flutter/cupertino.dart';
import '../data/models/booking_date_status.dart';

/// A custom month-grid calendar that decorates each day cell with a booking
/// status indicator.
///
/// Status rendering:
///   - confirmed  → red tint background + strikethrough over the day number
///   - pending    → yellow tint background + yellow indicator dot
///   - draft      → blue tint background + blue indicator dot
///
/// The [dateStatuses] map is keyed by ISO-8601 date strings ("yyyy-MM-dd").
/// Days not present in the map are rendered as plain, selectable cells.
///
/// The currently [selectedDate] is shown with the system accent circle (same
/// visual language as CupertinoDatePicker).  When the selected date has a
/// booking, a one-line subtitle is shown below the legend, e.g.
/// "Confirmed: The Grand Wedding".
class BookingCalendarPicker extends StatefulWidget {
  const BookingCalendarPicker({
    super.key,
    required this.selectedDate,
    required this.dateStatuses,
    required this.onDateSelected,
    this.firstDate,
    this.lastDate,
  });

  final DateTime selectedDate;

  /// Booking occupancy info keyed by "yyyy-MM-dd".
  final Map<String, BookingDateInfo> dateStatuses;

  final ValueChanged<DateTime> onDateSelected;

  /// Earliest selectable date. Defaults to 10 years before today.
  final DateTime? firstDate;

  /// Latest selectable date. Defaults to 10 years after today.
  final DateTime? lastDate;

  @override
  State<BookingCalendarPicker> createState() => _BookingCalendarPickerState();
}

class _BookingCalendarPickerState extends State<BookingCalendarPicker> {
  late DateTime _displayMonth; // year + month currently shown

  @override
  void initState() {
    super.initState();
    // Start the grid on the month containing the selected date.
    _displayMonth =
        DateTime(widget.selectedDate.year, widget.selectedDate.month);
  }

  DateTime get _firstDate =>
      widget.firstDate ?? DateTime(DateTime.now().year - 10);
  DateTime get _lastDate =>
      widget.lastDate ?? DateTime(DateTime.now().year + 10);

  bool get _canGoPrev {
    final prev = DateTime(_displayMonth.year, _displayMonth.month - 1);
    return !prev.isBefore(DateTime(_firstDate.year, _firstDate.month));
  }

  bool get _canGoNext {
    final next = DateTime(_displayMonth.year, _displayMonth.month + 1);
    return !next.isAfter(DateTime(_lastDate.year, _lastDate.month));
  }

  void _prevMonth() {
    if (!_canGoPrev) return;
    setState(() {
      _displayMonth =
          DateTime(_displayMonth.year, _displayMonth.month - 1);
    });
  }

  void _nextMonth() {
    if (!_canGoNext) return;
    setState(() {
      _displayMonth =
          DateTime(_displayMonth.year, _displayMonth.month + 1);
    });
  }

  // Normalise to midnight so comparisons are date-only.
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _isoKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final brightness = CupertinoTheme.brightnessOf(context);
    final isDark = brightness == Brightness.dark;

    final today = _dateOnly(DateTime.now());
    final selected = _dateOnly(widget.selectedDate);

    // Weekday of the 1st of the display month (1=Mon … 7=Sun in Dart).
    // We want Sunday-first grid (index 0 = Sunday), so shift accordingly.
    final firstOfMonth = DateTime(_displayMonth.year, _displayMonth.month, 1);
    // Dart weekday: Mon=1 … Sun=7. Convert to Sun=0 … Sat=6.
    final firstWeekdayOffset = firstOfMonth.weekday % 7;

    final daysInMonth = DateUtils.getDaysInMonth(
        _displayMonth.year, _displayMonth.month);

    // Total grid cells (always multiple of 7).
    final totalCells = firstWeekdayOffset + daysInMonth;
    final rowCount = (totalCells / 7).ceil();

    const weekdays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Month navigation header ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              CupertinoButton(
                padding: const EdgeInsets.all(8),
                onPressed: _canGoPrev ? _prevMonth : null,
                child: Icon(
                  CupertinoIcons.chevron_left,
                  size: 18,
                  color: _canGoPrev
                      ? CupertinoColors.activeBlue.resolveFrom(context)
                      : CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
              ),
              Expanded(
                child: Text(
                  // e.g. "March 2026"
                  _monthYearLabel(_displayMonth),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.all(8),
                onPressed: _canGoNext ? _nextMonth : null,
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 18,
                  color: _canGoNext
                      ? CupertinoColors.activeBlue.resolveFrom(context)
                      : CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),

        // ── Weekday labels ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: weekdays
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),

        const SizedBox(height: 4),

        // ── Day grid ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: List.generate(rowCount, (row) {
              return Row(
                children: List.generate(7, (col) {
                  final cellIndex = row * 7 + col;
                  final dayNumber = cellIndex - firstWeekdayOffset + 1;

                  // Empty cells before the 1st or after the last day.
                  if (dayNumber < 1 || dayNumber > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 44));
                  }

                  final cellDate = DateTime(
                      _displayMonth.year, _displayMonth.month, dayNumber);
                  final key = _isoKey(cellDate);
                  final info = widget.dateStatuses[key];
                  final isSelected = cellDate == selected;
                  final isToday = cellDate == today;

                  return Expanded(
                    child: _DayCell(
                      day: dayNumber,
                      isSelected: isSelected,
                      isToday: isToday,
                      info: info,
                      isDark: isDark,
                      onTap: () => widget.onDateSelected(cellDate),
                    ),
                  );
                }),
              );
            }),
          ),
        ),

        const SizedBox(height: 8),

        // ── Legend ──────────────────────────────────────────────────────
        _Legend(),

        // ── Selected-date booking subtitle ──────────────────────────────
        // Only rendered when the selected date has a booking.
        _SelectedDateSubtitle(
          info: widget.dateStatuses[_isoKey(selected)],
        ),
      ],
    );
  }

  String _monthYearLabel(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}

// ── Individual day cell ───────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.info,
    required this.isDark,
    required this.onTap,
  });

  final int day;
  final bool isSelected;
  final bool isToday;
  final BookingDateInfo? info;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = info?.status;

    // Selection circle takes visual priority over status background.
    final Color? bgColor = isSelected
        ? CupertinoColors.activeBlue.resolveFrom(context)
        : status?.cellColor(context);

    final Color textColor = isSelected
        ? CupertinoColors.white
        : (status != null
            ? status.accentColor(context)
            : CupertinoColors.label.resolveFrom(context));

    // Today gets a subtle ring when not selected.
    final bool showTodayRing = isToday && !isSelected;

    return Semantics(
      label: 'Date $day'
          '${status != null ? ', ${_semanticStatus(status, info!.bookingTitle)}' : ''}',
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: showTodayRing
                ? Border.all(
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                    width: 1.5,
                  )
                : null,
          ),
          child: Center(
            child: _DayLabel(
              day: day,
              textColor: textColor,
              strikethrough: !isSelected &&
                  (status?.showStrikethrough ?? false),
            ),
          ),
        ),
      ),
    );
  }

  String _semanticStatus(BookingDateStatus s, String title) => switch (s) {
        BookingDateStatus.confirmed => 'confirmed booking: $title',
        BookingDateStatus.pending => 'pending booking: $title',
        BookingDateStatus.draft => 'draft booking: $title',
      };
}

// ── Day number label with optional strikethrough ──────────────────────────────

class _DayLabel extends StatelessWidget {
  const _DayLabel({
    required this.day,
    required this.textColor,
    required this.strikethrough,
  });

  final int day;
  final Color textColor;
  final bool strikethrough;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$day',
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: textColor,
        decoration: strikethrough ? TextDecoration.lineThrough : null,
        decorationColor: textColor,
        decorationThickness: 2,
      ),
    );
  }
}

// ── Legend ────────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LegendItem(
            color: CupertinoColors.systemRed.resolveFrom(context),
            label: 'Confirmed',
            strikethrough: true,
          ),
          const SizedBox(width: 16),
          _LegendItem(
            color: CupertinoColors.systemYellow.resolveFrom(context),
            label: 'Pending',
          ),
          const SizedBox(width: 16),
          _LegendItem(
            color: CupertinoColors.systemBlue.resolveFrom(context),
            label: 'Draft',
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.strikethrough = false,
  });

  final Color color;
  final String label;
  final bool strikethrough;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
            decoration: strikethrough ? TextDecoration.lineThrough : null,
            decorationColor:
                CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ],
    );
  }
}

// ── Selected-date booking subtitle ───────────────────────────────────────────

/// Renders a single-line label below the legend when [info] is non-null.
///
/// Examples:
///   "Confirmed: The Grand Wedding"
///   "Pending: Summer Festival"
///
/// The label is coloured with the status's accent colour so it visually ties
/// back to the day cell tint.  An empty [SizedBox] is returned when the
/// selected date has no booking so the layout height stays stable.
class _SelectedDateSubtitle extends StatelessWidget {
  const _SelectedDateSubtitle({required this.info});

  final BookingDateInfo? info;

  @override
  Widget build(BuildContext context) {
    if (info == null) {
      // Stable minimum height so the calendar doesn't jump in/out.
      return const SizedBox(height: 28);
    }

    final label = switch (info!.status) {
      BookingDateStatus.confirmed => 'Confirmed',
      BookingDateStatus.pending => 'Pending',
      BookingDateStatus.draft => 'Draft',
    };

    final color = info!.status.accentColor(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Semantics(
        label: '$label booking: ${info!.bookingTitle}',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$label: ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            Flexible(
              child: Text(
                info!.bookingTitle,
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Re-export DateUtils so the widget file is self-contained (avoids a
// material import in what is otherwise a cupertino-only file).
class DateUtils {
  DateUtils._();

  static int getDaysInMonth(int year, int month) {
    // Day 0 of the next month = last day of this month.
    return DateTime(year, month + 1, 0).day;
  }
}
