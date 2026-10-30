import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/event_tabs.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';

EventDetail _event({
  List<Map<String, dynamic>>? timeline,
  Map<String, dynamic>? performance,
  Map<String, dynamic>? wedding,
  int? liveSessionId,
}) =>
    EventDetail.fromJson({
      'id': 1,
      'key': 'k',
      'title': 'Gig',
      'date': '2026-05-20',
      'can_write': true,
      'members': <dynamic>[],
      'timeline': timeline ?? <dynamic>[],
      'performance': performance,
      'wedding': wedding,
      'live_session_id': liveSessionId,
    });

void main() {
  group('visibleTabs', () {
    test('bare event shows only Overview and Notes', () {
      expect(visibleTabs(_event()), [EventTab.overview, EventTab.notes]);
    });

    test('Timeline needs timeline entries', () {
      final tabs = visibleTabs(_event(timeline: [
        {'title': 'Load in', 'time': '17:00'},
      ]));
      expect(tabs, [EventTab.overview, EventTab.timeline, EventTab.notes]);
    });

    test('Music appears for performance notes, songs or charts', () {
      for (final perf in [
        {'notes': 'Play it tight', 'songs': <dynamic>[], 'charts': <dynamic>[]},
        {
          'songs': [
            {'title': 'Song'}
          ],
          'charts': <dynamic>[]
        },
        {
          'songs': <dynamic>[],
          'charts': [
            {'title': 'Chart'}
          ]
        },
      ]) {
        expect(
            visibleTabs(_event(performance: perf)), contains(EventTab.music));
      }
    });

    test('empty performance does not add Music', () {
      final tabs = visibleTabs(
          _event(performance: {'songs': <dynamic>[], 'charts': <dynamic>[]}));
      expect(tabs, isNot(contains(EventTab.music)));
    });

    test('Music appears for wedding dances but not an empty wedding block', () {
      expect(
        visibleTabs(_event(wedding: {
          'dances': [
            {'title': 'first_dance', 'data': 'Song'}
          ]
        })),
        contains(EventTab.music),
      );
      expect(
        visibleTabs(_event(wedding: {'onsite': true, 'dances': <dynamic>[]})),
        isNot(contains(EventTab.music)),
      );
    });

    test('Music appears while a live session is running', () {
      expect(visibleTabs(_event(liveSessionId: 7)), contains(EventTab.music));
    });

    test('all tabs keep display order', () {
      final tabs = visibleTabs(_event(
        timeline: [
          {'title': 'Show', 'time': '19:00'}
        ],
        liveSessionId: 1,
      ));
      expect(tabs, EventTab.values);
    });
  });

  group('visibleTabs client requests', () {
    test('client song picks alone earn a Music tab', () {
      expect(visibleTabs(_event(), hasClientRequests: true),
          [EventTab.overview, EventTab.music, EventTab.notes]);
    });
  });

  group('resolveInitialTab', () {
    const visible = [EventTab.overview, EventTab.timeline, EventTab.notes];

    test('uses the remembered tab when it is visible', () {
      expect(resolveInitialTab('timeline', visible), EventTab.timeline);
      expect(resolveInitialTab('notes', visible), EventTab.notes);
    });

    test('falls back to Overview when the remembered tab is hidden', () {
      expect(resolveInitialTab('music', visible), EventTab.overview);
    });

    test('falls back to Overview for nothing stored or garbage', () {
      expect(resolveInitialTab(null, visible), EventTab.overview);
      expect(resolveInitialTab('bogus', visible), EventTab.overview);
    });
  });
}
