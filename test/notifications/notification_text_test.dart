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
}
