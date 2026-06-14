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
}
