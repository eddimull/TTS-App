import 'package:table_calendar/table_calendar.dart' show isSameDay;

import '../events/data/models/event_summary.dart';

/// The half-open date range `[lowerBound, end)` the dashboard list (and the
/// filter-aware empty state) consider "in range" for a focused month.
///
/// For the CURRENT month the lower bound is today, so already-passed days are
/// excluded; past/future months span the whole month. [now] is injected so the
/// logic is testable without the wall clock (see avoid-time-bomb-date-tests).
class FocusedMonthRange {
  const FocusedMonthRange(this.lowerBound, this.end);

  /// Inclusive lower bound — `max(monthStart, today)` for the current month.
  final DateTime lowerBound;

  /// Exclusive upper bound — the first day of the following month.
  final DateTime end;

  bool contains(DateTime date) =>
      !date.isBefore(lowerBound) && date.isBefore(end);

  factory FocusedMonthRange.of(DateTime focusedDay, DateTime now) {
    final monthStart = DateTime(focusedDay.year, focusedDay.month, 1);
    final monthEnd = DateTime(focusedDay.year, focusedDay.month + 1, 1);
    final today = DateTime(now.year, now.month, now.day);
    final lowerBound = today.isAfter(monthStart) && today.isBefore(monthEnd)
        ? today
        : monthStart;
    return FocusedMonthRange(lowerBound, monthEnd);
  }
}

/// Computes the events shown in the dashboard list beneath the calendar.
///
/// Pure function so the date logic is unit-testable without pumping a widget.
/// Pass [now] explicitly so tests can pin the clock (see
/// avoid-time-bomb-date-tests).
///
/// Behaviour:
/// - A day is selected → that day's events, or the single next-upcoming event
///   if the day is empty.
/// - No day selected → the focused month's events, sorted ascending. For the
///   CURRENT month the list starts from today (already-passed days this month
///   are hidden), matching the "Upcoming Events" header. Past/future months
///   show the whole month.
List<EventSummary> dashboardListEvents({
  required List<EventSummary> events,
  required DateTime focusedDay,
  required DateTime? selectedDay,
  required DateTime now,
}) {
  if (selectedDay != null) {
    final dayEvents =
        events.where((e) => isSameDay(e.parsedDate, selectedDay)).toList();
    if (dayEvents.isNotEmpty) return dayEvents;
    final later = events
        .where((e) => !e.parsedDate.isBefore(selectedDay))
        .toList()
      ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
    return later.take(1).toList();
  }

  final range = FocusedMonthRange.of(focusedDay, now);
  return events.where((e) => range.contains(e.parsedDate)).toList()
    ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
}
