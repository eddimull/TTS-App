import 'package:table_calendar/table_calendar.dart' show isSameDay;

import '../events/data/models/event_summary.dart';

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

  final monthStart = DateTime(focusedDay.year, focusedDay.month, 1);
  final monthEnd = DateTime(focusedDay.year, focusedDay.month + 1, 1);
  final today = DateTime(now.year, now.month, now.day);
  // For the current month, start the list from today rather than the 1st so
  // already-passed days don't clutter the upcoming list.
  final lowerBound = today.isAfter(monthStart) && today.isBefore(monthEnd)
      ? today
      : monthStart;

  return events
      .where(
        (e) =>
            !e.parsedDate.isBefore(lowerBound) &&
            e.parsedDate.isBefore(monthEnd),
      )
      .toList()
    ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
}
