import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';
import 'package:tts_bandmate/features/bookings/utils/booking_month_strip.dart';

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
  group('monthKeyFor', () {
    test('formats year-month with zero-padded month', () {
      expect(monthKeyFor(DateTime(2026, 3, 15)), '2026-03');
      expect(monthKeyFor(DateTime(2026, 12, 1)), '2026-12');
    });
  });

  group('buildMonthKeys', () {
    test('returns empty list for empty input', () {
      expect(buildMonthKeys(const []), isEmpty);
    });

    test('returns sorted unique month keys', () {
      final keys = buildMonthKeys([
        _b(1, '2026-03-10'),
        _b(2, '2026-01-15'),
        _b(3, '2026-03-22'),
        _b(4, '2025-12-01'),
      ]);
      expect(keys, ['2025-12', '2026-01', '2026-03']);
    });

    test('handles multi-year input', () {
      final keys = buildMonthKeys([
        _b(1, '2027-01-01'),
        _b(2, '2025-06-15'),
      ]);
      expect(keys, ['2025-06', '2027-01']);
    });
  });

  group('findNearestUpcomingIndex', () {
    test('returns null for empty list', () {
      expect(findNearestUpcomingIndex(const [], DateTime(2026, 5, 1)),
          isNull);
    });

    test('returns first booking on or after now', () {
      final list = [
        _b(1, '2026-01-01'),
        _b(2, '2026-05-15'),
        _b(3, '2026-08-01'),
      ];
      expect(findNearestUpcomingIndex(list, DateTime(2026, 5, 1)), 1);
    });

    test('treats today (date-only) as upcoming', () {
      final list = [
        _b(1, '2026-04-30'),
        _b(2, '2026-05-01'),
      ];
      expect(findNearestUpcomingIndex(list, DateTime(2026, 5, 1)), 1);
    });

    test('returns last index when all bookings are in the past', () {
      final list = [
        _b(1, '2026-01-01'),
        _b(2, '2026-02-01'),
      ];
      expect(findNearestUpcomingIndex(list, DateTime(2026, 5, 1)), 1);
    });

    test('returns 0 when all bookings are in the future', () {
      final list = [
        _b(1, '2026-06-01'),
        _b(2, '2026-07-01'),
      ];
      expect(findNearestUpcomingIndex(list, DateTime(2026, 5, 1)), 0);
    });

    test('input must already be sorted ascending', () {
      // Documents the contract — caller sorts; helper does not.
      final list = [
        _b(1, '2026-08-01'),
        _b(2, '2026-05-15'),
      ];
      // First element 2026-08-01 is on/after 2026-05-01, so index 0.
      expect(findNearestUpcomingIndex(list, DateTime(2026, 5, 1)), 0);
    });

    test('ignores time-of-day in now (afternoon today is still upcoming)',
        () {
      final list = [
        _b(1, '2026-04-30'),
        _b(2, '2026-05-01'),
      ];
      // 2:30pm on 2026-05-01 — today's booking should still be selected.
      expect(
        findNearestUpcomingIndex(list, DateTime(2026, 5, 1, 14, 30)),
        1,
      );
    });
  });
}
