import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/dashboard_list_filter.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

EventSummary evt(String key, DateTime date, {String source = 'booking'}) {
  final iso = '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  return EventSummary(
    key: key,
    title: '$key title',
    date: iso,
    eventSource: source,
  );
}

void main() {
  group('dashboardListEvents — current month starts from today', () {
    // Pin the clock to mid-month so there are clearly past and future days
    // within the same month.
    final now = DateTime(2026, 6, 15, 9, 0);
    final focused = DateTime(2026, 6, 15);

    test('hides days already passed in the current month', () {
      final events = [
        evt('past', DateTime(2026, 6, 1)),
        evt('yesterday', DateTime(2026, 6, 14)),
        evt('today', DateTime(2026, 6, 15)),
        evt('soon', DateTime(2026, 6, 20)),
      ];

      final result = dashboardListEvents(
        events: events,
        focusedDay: focused,
        selectedDay: null,
        now: now,
      );

      expect(
        result.map((e) => e.key),
        ['today', 'soon'],
        reason: 'current-month list should start at today, dropping past days',
      );
    });

    test('keeps an event dated today even with a time earlier than now', () {
      final events = [evt('today', DateTime(2026, 6, 15))];
      final result = dashboardListEvents(
        events: events,
        focusedDay: focused,
        selectedDay: null,
        now: DateTime(2026, 6, 15, 23, 59),
      );
      expect(result.map((e) => e.key), ['today']);
    });

    test('sorts the current-month list ascending by date', () {
      final events = [
        evt('later', DateTime(2026, 6, 28)),
        evt('today', DateTime(2026, 6, 15)),
        evt('mid', DateTime(2026, 6, 20)),
      ];
      final result = dashboardListEvents(
        events: events,
        focusedDay: focused,
        selectedDay: null,
        now: now,
      );
      expect(result.map((e) => e.key), ['today', 'mid', 'later']);
    });
  });

  group('dashboardListEvents — other months unchanged', () {
    final now = DateTime(2026, 6, 15, 9, 0);

    test('a PAST month shows the whole month including early days', () {
      final focused = DateTime(2026, 5, 15);
      final events = [
        evt('may1', DateTime(2026, 5, 1)),
        evt('may20', DateTime(2026, 5, 20)),
      ];
      final result = dashboardListEvents(
        events: events,
        focusedDay: focused,
        selectedDay: null,
        now: now,
      );
      expect(result.map((e) => e.key), ['may1', 'may20']);
    });

    test('a FUTURE month shows the whole month from the 1st', () {
      final focused = DateTime(2026, 7, 15);
      final events = [
        evt('jul1', DateTime(2026, 7, 1)),
        evt('jul10', DateTime(2026, 7, 10)),
      ];
      final result = dashboardListEvents(
        events: events,
        focusedDay: focused,
        selectedDay: null,
        now: now,
      );
      expect(result.map((e) => e.key), ['jul1', 'jul10']);
    });
  });

  group('FocusedMonthRange — shared lower-bound rule', () {
    final now = DateTime(2026, 6, 15, 9, 0);

    test('current month lower bound is today, end is next month', () {
      final r = FocusedMonthRange.of(DateTime(2026, 6, 15), now);
      expect(r.lowerBound, DateTime(2026, 6, 15));
      expect(r.end, DateTime(2026, 7, 1));
      expect(r.contains(DateTime(2026, 6, 14)), isFalse); // yesterday excluded
      expect(r.contains(DateTime(2026, 6, 15)), isTrue); // today included
      expect(r.contains(DateTime(2026, 6, 30)), isTrue);
      expect(r.contains(DateTime(2026, 7, 1)), isFalse); // end exclusive
    });

    test('past month lower bound is the 1st', () {
      final r = FocusedMonthRange.of(DateTime(2026, 5, 10), now);
      expect(r.lowerBound, DateTime(2026, 5, 1));
      expect(r.contains(DateTime(2026, 5, 1)), isTrue);
    });

    test('future month lower bound is the 1st', () {
      final r = FocusedMonthRange.of(DateTime(2026, 7, 10), now);
      expect(r.lowerBound, DateTime(2026, 7, 1));
      expect(r.contains(DateTime(2026, 7, 1)), isTrue);
    });
  });

  group('dashboardListEvents — selected day behaviour preserved', () {
    final now = DateTime(2026, 6, 15, 9, 0);
    final focused = DateTime(2026, 6, 15);

    test('selected day with events returns that day only', () {
      final events = [
        evt('the-day', DateTime(2026, 6, 10)),
        evt('other', DateTime(2026, 6, 12)),
      ];
      final result = dashboardListEvents(
        events: events,
        focusedDay: focused,
        selectedDay: DateTime(2026, 6, 10),
        now: now,
      );
      expect(result.map((e) => e.key), ['the-day']);
    });

    test('empty selected day falls back to the next upcoming event', () {
      final events = [
        evt('past', DateTime(2026, 6, 5)),
        evt('next', DateTime(2026, 6, 18)),
        evt('later', DateTime(2026, 6, 25)),
      ];
      final result = dashboardListEvents(
        events: events,
        focusedDay: focused,
        selectedDay: DateTime(2026, 6, 10),
        now: now,
      );
      expect(result.map((e) => e.key), ['next']);
    });
  });
}
