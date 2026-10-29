import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/event_header_times.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';

EventDetail _event({
  String? time,
  String? startTime,
  String? endTime,
  List<Map<String, dynamic>> timeline = const [],
  String? venue,
}) =>
    EventDetail.fromJson({
      'id': 1,
      'key': 'k',
      'title': 'Gig',
      'date': '2026-11-07',
      'time': time,
      'start_time': startTime,
      'end_time': endTime,
      'venue_name': venue,
      'can_write': true,
      'members': <dynamic>[],
      'timeline': timeline,
    });

void main() {
  group('headerTimes', () {
    test('everything missing gives nulls', () {
      final t = headerTimes(_event());
      expect(t.loadIn, isNull);
      expect(t.show, isNull);
      expect(t.end, isNull);
    });

    test('load-in matches "Load in" and "Load-In" loosely', () {
      for (final title in ['Load in', 'Load-in', 'LOAD-IN', 'Band load in']) {
        final t = headerTimes(_event(timeline: [
          {'title': title, 'time': '2026-11-07 14:30'},
        ]));
        expect(t.loadIn, '2026-11-07 14:30', reason: title);
      }
    });

    test('show prefers the event start time over the timeline', () {
      final t = headerTimes(_event(startTime: '16:30', timeline: [
        {'title': 'Show time', 'time': '2026-11-07 17:00'},
      ]));
      expect(t.show, '16:30');
    });

    test('show falls back to a "show" then a "start" timeline entry', () {
      expect(
        headerTimes(_event(timeline: [
          {'title': 'Ceremony starts', 'time': '15:00'},
          {'title': 'Show', 'time': '16:30'},
        ])).show,
        '16:30',
      );
      expect(
        headerTimes(_event(timeline: [
          {'title': 'Set 1 start', 'time': '16:45'},
        ])).show,
        '16:45',
      );
    });

    test('load-in entry is never taken as the show', () {
      final t = headerTimes(_event(timeline: [
        {'title': 'Load in for show', 'time': '14:00'},
      ]));
      expect(t.loadIn, '14:00');
      expect(t.show, isNull);
    });

    test('end prefers endTime, then an "end" timeline entry', () {
      expect(headerTimes(_event(endTime: '23:00')).end, '23:00');
      expect(
        headerTimes(_event(timeline: [
          {'title': 'Band end', 'time': '2026-11-07 23:30'},
        ])).end,
        '2026-11-07 23:30',
      );
    });

    test('"weekend" style words do not count as end', () {
      final t = headerTimes(_event(timeline: [
        {'title': 'Weekend special', 'time': '20:00'},
      ]));
      expect(t.end, isNull);
    });

    test('entries without a time are skipped', () {
      final t = headerTimes(_event(timeline: [
        {'title': 'Load in'},
      ]));
      expect(t.loadIn, isNull);
    });
  });

  group('collapsedHeaderLine', () {
    test('date, show time and venue', () {
      final line =
          collapsedHeaderLine(_event(startTime: '16:30', venue: 'Il Mercato'));
      expect(line, 'Sat, Nov 7 · Show 4:30 PM · Il Mercato');
    });

    test('leaves out what is missing', () {
      expect(collapsedHeaderLine(_event()), 'Sat, Nov 7');
      expect(collapsedHeaderLine(_event(venue: 'Il Mercato')),
          'Sat, Nov 7 · Il Mercato');
    });
  });
}
