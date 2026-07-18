import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/utils/message_time.dart';

void main() {
  final now = DateTime(2026, 7, 18, 20, 0); // Sat Jul 18 2026, 8:00 PM local

  group('needsDateSeparator', () {
    test('first message always gets a separator', () {
      expect(needsDateSeparator(null, DateTime(2026, 7, 18, 9, 0)), isTrue);
    });

    test('same day within an hour: no separator', () {
      expect(
        needsDateSeparator(
            DateTime(2026, 7, 18, 9, 0), DateTime(2026, 7, 18, 9, 59)),
        isFalse,
      );
    });

    test('same day but more than an hour apart: separator', () {
      expect(
        needsDateSeparator(
            DateTime(2026, 7, 18, 9, 0), DateTime(2026, 7, 18, 10, 1)),
        isTrue,
      );
    });

    test('day boundary: separator even when minutes apart', () {
      expect(
        needsDateSeparator(
            DateTime(2026, 7, 17, 23, 55), DateTime(2026, 7, 18, 0, 5)),
        isTrue,
      );
    });
  });

  group('dateSeparatorLabel', () {
    test('same day as now: Today + time', () {
      expect(dateSeparatorLabel(DateTime(2026, 7, 18, 15, 42), now: now),
          'Today 3:42 PM');
    });

    test('previous day: Yesterday + time', () {
      expect(dateSeparatorLabel(DateTime(2026, 7, 17, 9, 10), now: now),
          'Yesterday 9:10 AM');
    });

    test('within the last week: weekday + time', () {
      // Jul 14 2026 is a Tuesday, 4 days before `now`.
      expect(dateSeparatorLabel(DateTime(2026, 7, 14, 18, 30), now: now),
          'Tuesday 6:30 PM');
    });

    test('older than a week: full date + time', () {
      expect(dateSeparatorLabel(DateTime(2026, 6, 3, 15, 42), now: now),
          'Jun 3, 2026 3:42 PM');
    });

    test('exactly 7 days ago is full date, not weekday (avoids ambiguity)',
        () {
      expect(dateSeparatorLabel(DateTime(2026, 7, 11, 8, 0), now: now),
          'Jul 11, 2026 8:00 AM');
    });
  });

  group('bubbleTimeLabel', () {
    test('same day: time only', () {
      expect(
          bubbleTimeLabel(DateTime(2026, 7, 18, 15, 42), now: now), '3:42 PM');
    });

    test('other day: date + time', () {
      expect(bubbleTimeLabel(DateTime(2026, 6, 3, 15, 42), now: now),
          'Jun 3, 2026 3:42 PM');
    });
  });
}
