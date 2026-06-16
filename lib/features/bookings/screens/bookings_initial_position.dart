import '../data/models/booking_summary.dart';
import '../utils/booking_month_strip.dart'
    show findNearestUpcomingIndex, monthKeyFor;

/// Index into the rendered items list (headers + cards) that the bookings
/// list should be initially scrolled to: the month header of the
/// nearest-upcoming booking (or, when everything is in the past,
/// `findNearestUpcomingIndex` returns the last booking, so we land on the most
/// recent month).
///
/// Returns 0 for an empty list. Falls back to the last header index when the
/// nearest booking's month is absent from [monthHeaderIndex] — this happens
/// when [sortedFiltered] is the pre-search list but [monthHeaderIndex] is built
/// from the search-narrowed items, so an active search can hide that month.
///
/// Caller adds any top-sentinel offset (loadEarlier spinner) separately.
int initialBookingScrollIndex({
  required List<BookingSummary> sortedFiltered,
  required Map<String, int> monthHeaderIndex,
  required DateTime now,
}) {
  if (sortedFiltered.isEmpty || monthHeaderIndex.isEmpty) return 0;

  final nearestIdx = findNearestUpcomingIndex(sortedFiltered, now);
  if (nearestIdx != null) {
    final key = monthKeyFor(sortedFiltered[nearestIdx].parsedStartDate);
    final headerIdx = monthHeaderIndex[key];
    if (headerIdx != null) return headerIdx;
  }
  return monthHeaderIndex.values.reduce((a, b) => a > b ? a : b);
}
