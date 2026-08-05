import '../../../shared/utils/day_key.dart';
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
    var day = dayKey(checkIn);
    final lastDay = dayKey(checkOut);
    if (lastDay.isBefore(day)) continue;
    while (!day.isAfter(lastDay)) {
      map.putIfAbsent(day, () => []).add(LodgingDayEntry(
            lodging: stay,
            isCheckIn: day == dayKey(checkIn),
            isCheckOut: day == lastDay,
          ));
      day = day.add(const Duration(days: 1));
    }
  }
  return map;
}
