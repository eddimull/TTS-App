import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/notifications/data/notification_text.dart';

void main() {
  group('firstTimelineItem', () {
    test('returns the entry with the earliest parseable time', () {
      final timeline = [
        const EventTimelineEntry(title: 'Show', time: '2026-06-13T19:00:00'),
        const EventTimelineEntry(title: 'Load In', time: '2026-06-13T14:00:00'),
        const EventTimelineEntry(title: 'Sound Check', time: '2026-06-13T17:00:00'),
      ];
      final first = firstTimelineItem(timeline);
      expect(first?.title, 'Load In');
    });

    test('ignores entries with null or unparseable time', () {
      final timeline = [
        const EventTimelineEntry(title: 'No Time', time: null),
        const EventTimelineEntry(title: 'Load In', time: '2026-06-13T14:00:00'),
        const EventTimelineEntry(title: 'Garbage', time: 'not-a-time'),
      ];
      final first = firstTimelineItem(timeline);
      expect(first?.title, 'Load In');
    });

    test('returns null when no entry has a parseable time', () {
      final timeline = [
        const EventTimelineEntry(title: 'A', time: null),
        const EventTimelineEntry(title: 'B', time: 'nope'),
      ];
      expect(firstTimelineItem(timeline), isNull);
    });

    test('returns null for an empty timeline', () {
      expect(firstTimelineItem(const []), isNull);
    });
  });

  group('formatClock', () {
    test('formats an afternoon ISO time as h:mma lowercase', () {
      expect(formatClock('2026-06-13T14:00:00'), '2:00pm');
    });
    test('formats a morning time', () {
      expect(formatClock('2026-06-13T09:05:00'), '9:05am');
    });
    test('formats midnight and noon', () {
      expect(formatClock('2026-06-13T00:00:00'), '12:00am');
      expect(formatClock('2026-06-13T12:00:00'), '12:00pm');
    });
    test('formats a bare HH:mm', () {
      expect(formatClock('19:30'), '7:30pm');
    });
    test('returns null for unparseable input', () {
      expect(formatClock('nope'), isNull);
      expect(formatClock(null), isNull);
    });
  });

  group('buildReminderBody', () {
    test('venue + load-in + show', () {
      final body = buildReminderBody(
        venue: 'The Blue Room',
        firstItemTitle: 'Load In',
        firstItemTime: '2026-06-13T14:00:00',
        showTime: '2026-06-13T19:00:00',
      );
      expect(body, 'The Blue Room · Load In 2:00pm, Show 7:00pm');
    });

    test('venue + single item (show equals first, collapses to one line)', () {
      final body = buildReminderBody(
        venue: 'The Blue Room',
        firstItemTitle: 'Show',
        firstItemTime: '2026-06-13T19:00:00',
        showTime: '2026-06-13T19:00:00',
      );
      expect(body, 'The Blue Room · Show 7:00pm');
    });

    test('venue + first item only, no show time', () {
      final body = buildReminderBody(
        venue: 'The Blue Room',
        firstItemTitle: 'Load In',
        firstItemTime: '2026-06-13T14:00:00',
        showTime: null,
      );
      expect(body, 'The Blue Room · Load In 2:00pm');
    });

    test('no venue, has times', () {
      final body = buildReminderBody(
        venue: null,
        firstItemTitle: 'Load In',
        firstItemTime: '2026-06-13T14:00:00',
        showTime: '2026-06-13T19:00:00',
      );
      expect(body, 'Load In 2:00pm, Show 7:00pm');
    });

    test('no venue, no usable times', () {
      final body = buildReminderBody(
        venue: null,
        firstItemTitle: null,
        firstItemTime: null,
        showTime: null,
      );
      expect(body, 'You have an event today');
    });

    test('venue present but no usable times falls back to event-today with venue', () {
      final body = buildReminderBody(
        venue: 'The Blue Room',
        firstItemTitle: null,
        firstItemTime: null,
        showTime: null,
      );
      expect(body, 'The Blue Room · You have an event today');
    });

    test('drops a titled first item whose time is unparseable', () {
      final body = buildReminderBody(
        venue: 'The Blue Room',
        firstItemTitle: 'Load In',
        firstItemTime: 'not-a-time',
        showTime: '2026-06-13T19:00:00',
      );
      expect(body, 'The Blue Room · Show 7:00pm');
    });
  });
}
