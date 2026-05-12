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
    set.add(monthKeyFor(b.parsedStartDate));
  }
  final list = set.toList()..sort();
  return list;
}

/// Returns the index of the first booking in [bookings] whose `parsedStartDate`
/// is on or after the start of [now]'s day. Falls back to the last index
/// when every booking is in the past. Returns `null` for an empty list.
///
/// [now]'s time-of-day is ignored — passing `DateTime.now()` at any time
/// today selects today's booking if one exists.
///
/// **Contract:** [bookings] must already be sorted ascending by date —
/// the helper does not sort.
int? findNearestUpcomingIndex(List<BookingSummary> bookings, DateTime now) {
  if (bookings.isEmpty) return null;
  final today = DateTime(now.year, now.month, now.day);
  for (var i = 0; i < bookings.length; i++) {
    if (!bookings[i].parsedStartDate.isBefore(today)) return i;
  }
  return bookings.length - 1;
}
