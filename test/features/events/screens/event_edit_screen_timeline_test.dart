/// End-to-end widget test for the timeline field on EventEditScreen.
///
/// Regression coverage for the bug where edits to the timeline list were
/// dropped on save: the screen mutated `_timeline` locally but neither
/// `_save()` nor `EventsRepository.updateEvent` had the wiring to send
/// the list to the API.
///
/// These tests pump the real `EventEditScreen` against a fake repository
/// and verify that the `timeline` argument reaching `updateEvent` reflects
/// what the user sees on screen.
library;

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/events_repository.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/screens/event_edit_screen.dart';

/// Fake repository that records the kwargs passed to [updateEvent].
///
/// Subclasses the real repository so any methods we don't exercise still
/// exist with their real signatures — but those methods would hit the
/// (unused) `Dio` and fail loudly if the screen ever started calling them.
class _RecordingEventsRepository extends EventsRepository {
  _RecordingEventsRepository() : super(Dio());

  List<EventTimelineEntry>? lastTimeline;
  int updateCallCount = 0;

  @override
  Future<void> updateEvent(
    String key, {
    String? title,
    String? date,
    String? startTime,
    String? endTime,
    String? venueName,
    String? venueAddress,
    String? price,
    String? notes,
    List<EventTimelineEntry>? timeline,
  }) async {
    updateCallCount++;
    lastTimeline = timeline;
  }
}

/// Builds a minimal writable EventDetail with the given timeline entries.
/// No attachments / no wedding so the only `minus_circle` icons on screen
/// belong to the timeline rows.
EventDetail _makeDetailWithTimeline(List<Map<String, String?>> timeline) =>
    EventDetail.fromJson({
      'id': 1,
      'key': 'evt-1',
      'title': 'Test Event',
      'date': '2026-04-15',
      'can_write': true,
      'members': [],
      'timeline': timeline,
    });

/// Pumps EventEditScreen inside a CupertinoApp that gives it a real
/// navigation stack (so the screen's `Navigator.pop` on save succeeds).
Future<void> _pumpEditScreen(
  WidgetTester tester, {
  required EventDetail event,
  required _RecordingEventsRepository repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eventsRepositoryProvider.overrideWithValue(repo),
      ],
      child: CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                child: const Text('open'),
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => EventEditScreen(event: event),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('EventEditScreen timeline persistence', () {
    testWidgets(
      'sends current timeline to updateEvent on Save (no edits)',
      (tester) async {
        final repo = _RecordingEventsRepository();
        final event = _makeDetailWithTimeline([
          {'title': 'Load-in', 'time': '2026-04-15 16:00'},
          {'title': 'Soundcheck', 'time': '2026-04-15 17:30'},
        ]);

        await _pumpEditScreen(tester, event: event, repo: repo);

        // Sanity: scroll the form until the timeline section is visible,
        // then confirm both entries rendered.
        await tester.scrollUntilVisible(
          find.text('Load-in'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Load-in'), findsOneWidget);
        expect(find.text('Soundcheck'), findsOneWidget);

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(repo.updateCallCount, 1);
        expect(repo.lastTimeline, isNotNull);
        expect(repo.lastTimeline!.length, 2);
        expect(repo.lastTimeline![0].title, 'Load-in');
        expect(repo.lastTimeline![0].time, '2026-04-15 16:00');
        expect(repo.lastTimeline![1].title, 'Soundcheck');
        expect(repo.lastTimeline![1].time, '2026-04-15 17:30');
      },
    );

    testWidgets(
      'removing a timeline entry persists the shorter list on Save',
      (tester) async {
        final repo = _RecordingEventsRepository();
        final event = _makeDetailWithTimeline([
          {'title': 'Load-in', 'time': '2026-04-15 16:00'},
          {'title': 'Soundcheck', 'time': '2026-04-15 17:30'},
        ]);

        await _pumpEditScreen(tester, event: event, repo: repo);

        // Scroll the timeline section into view. The fixture has no
        // attachments and no wedding dances, so once visible, every
        // `minus_circle` belongs to a timeline-row delete button.
        await tester.scrollUntilVisible(
          find.text('Load-in'),
          200,
          scrollable: find.byType(Scrollable).first,
        );

        final deletes = find.byIcon(CupertinoIcons.minus_circle);
        expect(
          deletes,
          findsNWidgets(2),
          reason: 'expected exactly two timeline delete buttons',
        );
        await tester.tap(deletes.first);
        await tester.pumpAndSettle();

        expect(find.text('Load-in'), findsNothing);
        expect(find.text('Soundcheck'), findsOneWidget);

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(repo.updateCallCount, 1);
        expect(repo.lastTimeline, isNotNull);
        expect(repo.lastTimeline!.length, 1);
        expect(repo.lastTimeline!.single.title, 'Soundcheck');
        expect(repo.lastTimeline!.single.time, '2026-04-15 17:30');
      },
    );

    testWidgets(
      'empty timeline is sent as an empty list (clears server-side)',
      (tester) async {
        final repo = _RecordingEventsRepository();
        final event = _makeDetailWithTimeline(const []);

        await _pumpEditScreen(tester, event: event, repo: repo);

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(repo.updateCallCount, 1);
        expect(repo.lastTimeline, isNotNull);
        expect(repo.lastTimeline, isEmpty);
      },
    );
  });
}
