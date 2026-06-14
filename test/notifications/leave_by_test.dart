import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/leave_by.dart';

void main() {
  group('departureTime', () {
    test('subtracts travel from first-item time', () {
      final first = DateTime(2026, 6, 14, 19, 0);
      final dep = departureTime(firstItem: first, travel: const Duration(minutes: 45));
      expect(dep, DateTime(2026, 6, 14, 18, 15));
    });
  });

  group('remindAt', () {
    test('is 15 minutes before departure', () {
      final dep = DateTime(2026, 6, 14, 18, 15);
      expect(remindAt(dep), DateTime(2026, 6, 14, 18, 0));
    });
  });

  group('hasAlreadyLeft', () {
    test('true when within arrival radius', () {
      expect(
        hasAlreadyLeft(
          travelToVenue: const Duration(minutes: 5),
          timeUntilFirstItem: const Duration(minutes: 60),
          metersToVenue: 100,
          pastDeparture: false,
        ),
        true,
      );
    });

    test('true when en route and past departure with time to spare', () {
      expect(
        hasAlreadyLeft(
          travelToVenue: const Duration(minutes: 20),
          timeUntilFirstItem: const Duration(minutes: 40),
          metersToVenue: 8000,
          pastDeparture: true,
        ),
        true,
      );
    });

    test('false when far away and not yet departed', () {
      expect(
        hasAlreadyLeft(
          travelToVenue: const Duration(minutes: 40),
          timeUntilFirstItem: const Duration(minutes: 60),
          metersToVenue: 30000,
          pastDeparture: false,
        ),
        false,
      );
    });

    test('false when past departure but travel no longer fits (running late)', () {
      expect(
        hasAlreadyLeft(
          travelToVenue: const Duration(minutes: 50),
          timeUntilFirstItem: const Duration(minutes: 40),
          metersToVenue: 30000,
          pastDeparture: true,
        ),
        false,
      );
    });
  });
}
