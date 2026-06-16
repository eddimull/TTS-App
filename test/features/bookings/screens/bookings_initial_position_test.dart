import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';
import 'package:tts_bandmate/features/bookings/screens/bookings_initial_position.dart';

BookingSummary _b(int id, String date) => BookingSummary(
      id: id,
      name: 'b$id',
      startDate: date,
      endDate: date,
      eventCount: 1,
      isMultiEvent: false,
      isPaid: false,
      contacts: const [],
    );

void main() {
  group('initialBookingScrollIndex', () {
    test('returns header index of the nearest-upcoming booking', () {
      final sorted = [_b(1, '2026-04-15'), _b(2, '2026-06-10'), _b(3, '2026-07-01')];
      final monthHeaderIndex = {'2026-04': 0, '2026-06': 2, '2026-07': 4};
      final now = DateTime(2026, 5, 15);

      final idx = initialBookingScrollIndex(
        sortedFiltered: sorted,
        monthHeaderIndex: monthHeaderIndex,
        now: now,
      );
      expect(idx, 2);
    });

    test('returns last header index when nothing is upcoming', () {
      final sorted = [_b(1, '2026-01-15'), _b(2, '2026-02-10')];
      final monthHeaderIndex = {'2026-01': 0, '2026-02': 2};
      final now = DateTime(2026, 5, 15);

      final idx = initialBookingScrollIndex(
        sortedFiltered: sorted,
        monthHeaderIndex: monthHeaderIndex,
        now: now,
      );
      expect(idx, 2);
    });

    test('returns 0 for an empty list', () {
      final idx = initialBookingScrollIndex(
        sortedFiltered: const [],
        monthHeaderIndex: const {},
        now: DateTime(2026, 5, 15),
      );
      expect(idx, 0);
    });

    test(
        'falls back to last header when nearest month is missing from the index',
        () {
      // Mirrors an active search: the nearest-upcoming booking is in June, but
      // search has narrowed the rendered headers so June is absent. The helper
      // must fall back to the last header index present (July, index 4).
      final sorted = [_b(1, '2026-04-15'), _b(2, '2026-06-10'), _b(3, '2026-07-01')];
      final monthHeaderIndex = {'2026-04': 0, '2026-07': 4}; // no '2026-06'
      final now = DateTime(2026, 5, 15);

      final idx = initialBookingScrollIndex(
        sortedFiltered: sorted,
        monthHeaderIndex: monthHeaderIndex,
        now: now,
      );
      expect(idx, 4);
    });
  });
}
