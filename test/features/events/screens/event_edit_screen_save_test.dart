/// End-to-end widget tests for the EventEditScreen save path.
///
/// These tests exist because the screen has historically been a silent
/// drop-on-the-floor for fields the user edits — `_save()` builds an
/// `updateEvent` call by hand, and any field that's tracked in state but
/// not listed in that call disappears on submit. The `round-trip` test
/// below is the safety net: it loads an event with non-default values
/// for **every** field the screen tracks, taps Save without editing
/// anything, and asserts each value reappears in the captured repo
/// payload. If you add a new field to the screen, update the fixture —
/// otherwise this test breaks loudly.
library;

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/events_repository.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/screens/event_edit_screen.dart';

/// Fake repository that records every kwarg passed to [updateEvent].
///
/// Subclasses the real repository so signature drift is a compile error;
/// the unused `Dio` would blow up loudly if the screen called any other
/// method we haven't overridden.
class _RecordingEventsRepository extends EventsRepository {
  _RecordingEventsRepository() : super(Dio());

  int updateCallCount = 0;
  String? lastTitle;
  String? lastDate;
  String? lastStartTime;
  String? lastEndTime;
  String? lastVenueName;
  String? lastVenueAddress;
  String? lastNotes;
  String? lastAttire;
  List<EventTimelineEntry>? lastTimeline;
  bool? lastIsPublic;
  bool? lastOutside;
  bool? lastBacklineProvided;
  bool? lastProductionNeeded;
  List<Map<String, dynamic>>? lastLodging;
  Map<String, dynamic>? lastWedding;

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
    String? attire,
    List<EventTimelineEntry>? timeline,
    bool? isPublic,
    bool? outside,
    bool? backlineProvided,
    bool? productionNeeded,
    List<Map<String, dynamic>>? lodging,
    Map<String, dynamic>? wedding,
  }) async {
    updateCallCount++;
    lastTitle = title;
    lastDate = date;
    lastStartTime = startTime;
    lastEndTime = endTime;
    lastVenueName = venueName;
    lastVenueAddress = venueAddress;
    lastNotes = notes;
    lastAttire = attire;
    lastTimeline = timeline;
    lastIsPublic = isPublic;
    lastOutside = outside;
    lastBacklineProvided = backlineProvided;
    lastProductionNeeded = productionNeeded;
    lastLodging = lodging;
    lastWedding = wedding;
  }
}

/// Pumps EventEditScreen inside a CupertinoApp with a real navigation
/// stack so the screen's `Navigator.pop` on save succeeds.
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

/// Finds the CupertinoSwitch sitting in the same Row as [label].
Finder _switchForLabel(String label) => find.descendant(
      of: find.ancestor(
        of: find.text(label),
        matching: find.byType(Row),
      ),
      matching: find.byType(CupertinoSwitch),
    );

/// Scrolls until the row containing [label] is centered enough in the
/// viewport that the right-aligned switch is both below the nav bar and
/// above the bottom edge. Plain `scrollUntilVisible` aligns to top — but
/// the screen's CupertinoNavigationBar overlaps the top, swallowing taps.
Future<void> _scrollLabelIntoCenter(WidgetTester tester, String label) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(find.text(label), 200, scrollable: scrollable);
  // Nudge content downward by ~80px so the row sits clear of the nav bar
  // (the nav bar is ~44pt tall on Cupertino).
  await tester.drag(scrollable, const Offset(0, 80));
  await tester.pumpAndSettle();
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

/// EventDetail with non-default, distinct values for **every** field the
/// screen tracks. Used as the canonical "the screen should send all of
/// this back unchanged" payload for the round-trip test.
EventDetail _fullyPopulatedEvent() => EventDetail.fromJson({
      'id': 1,
      'key': 'evt-1',
      'title': 'Original Title',
      'date': '2026-04-15',
      'start_time': '19:00',
      'end_time': '22:00',
      'venue_name': 'Original Venue',
      'venue_address': '123 Original St',
      'notes': 'Original notes here.',
      'attire': 'All Black',
      'can_write': true,
      'members': [],
      'timeline': [
        {'title': 'Load-in', 'time': '2026-04-15 16:00'},
        {'title': 'Soundcheck', 'time': '2026-04-15 17:30'},
      ],
      'is_public': true,
      'outside': false,
      'backline_provided': true,
      'production_needed': false,
      'lodging': [
        {'title': 'Provided', 'type': 'checkbox', 'data': true},
        {'title': 'location', 'type': 'text', 'data': 'Hilton Riverwalk'},
        {'title': 'check_in', 'type': 'text', 'data': '15:00'},
        {'title': 'check_out', 'type': 'text', 'data': '11:00'},
      ],
      'wedding': {
        'onsite': true,
        'dances': [
          {'title': 'first_dance', 'data': 'At Last - Etta James'},
          {'title': 'father_daughter', 'data': 'My Girl - Temptations'},
        ],
      },
    });

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

void main() {
  // ── Round-trip safety net ─────────────────────────────────────────────────

  group('EventEditScreen.save round-trip', () {
    testWidgets(
      'every screen field flows through to updateEvent unchanged',
      (tester) async {
        // If you add a new field to EventEditScreen, add it to
        // _fullyPopulatedEvent above AND add an assertion here. This
        // test exists to catch "the screen edits X but X never reaches
        // the API" — a bug class this screen has fallen into multiple
        // times.
        final repo = _RecordingEventsRepository();
        final event = _fullyPopulatedEvent();

        await _pumpEditScreen(tester, event: event, repo: repo);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(repo.updateCallCount, 1);

        // Scalar fields.
        expect(repo.lastTitle, 'Original Title');
        expect(repo.lastDate, '2026-04-15');
        expect(repo.lastStartTime, '19:00');
        expect(repo.lastEndTime, '22:00');
        expect(repo.lastVenueName, 'Original Venue');
        expect(repo.lastVenueAddress, '123 Original St');
        expect(repo.lastNotes, 'Original notes here.');
        expect(repo.lastAttire, 'All Black');

        // Flag toggles.
        expect(repo.lastIsPublic, isTrue);
        expect(repo.lastOutside, isFalse);
        expect(repo.lastBacklineProvided, isTrue);
        expect(repo.lastProductionNeeded, isFalse);

        // Timeline.
        expect(repo.lastTimeline, isNotNull);
        expect(repo.lastTimeline!.length, 2);
        expect(repo.lastTimeline![0].title, 'Load-in');
        expect(repo.lastTimeline![0].time, '2026-04-15 16:00');
        expect(repo.lastTimeline![1].title, 'Soundcheck');
        expect(repo.lastTimeline![1].time, '2026-04-15 17:30');

        // Lodging.
        expect(repo.lastLodging, isNotNull);
        expect(repo.lastLodging!.length, 4);
        expect(repo.lastLodging![0],
            {'title': 'Provided', 'type': 'checkbox', 'data': true});
        expect(repo.lastLodging![1],
            {'title': 'location', 'type': 'text', 'data': 'Hilton Riverwalk'});
        expect(repo.lastLodging![2],
            {'title': 'check_in', 'type': 'text', 'data': '15:00'});
        expect(repo.lastLodging![3],
            {'title': 'check_out', 'type': 'text', 'data': '11:00'});

        // Wedding.
        expect(repo.lastWedding, isNotNull);
        expect(repo.lastWedding!['onsite'], isTrue);
        final dances = repo.lastWedding!['dances'] as List;
        expect(dances.length, 2);
        expect(dances[0],
            {'title': 'first_dance', 'data': 'At Last - Etta James'});
        expect(dances[1],
            {'title': 'father_daughter', 'data': 'My Girl - Temptations'});
      },
    );

    testWidgets(
      'omits wedding when the event has no wedding block',
      (tester) async {
        // Wedding is the only field whose absence on the loaded model
        // means "do not send this key at all" rather than "send a null."
        final repo = _RecordingEventsRepository();
        final event = EventDetail.fromJson({
          'id': 1,
          'key': 'evt-1',
          'title': 'Non-Wedding Event',
          'date': '2026-04-15',
          'can_write': true,
          'members': [],
        });

        await _pumpEditScreen(tester, event: event, repo: repo);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(repo.updateCallCount, 1);
        expect(repo.lastWedding, isNull);
      },
    );

    testWidgets(
      'omits null flag toggles instead of sending them as false',
      (tester) async {
        // The four flag toggles use null to mean "this event doesn't
        // track this field." The screen must not coerce null → false on
        // save, or it would invent values the user never set.
        final repo = _RecordingEventsRepository();
        final event = EventDetail.fromJson({
          'id': 1,
          'key': 'evt-1',
          'title': 'Sparse Event',
          'date': '2026-04-15',
          'can_write': true,
          'members': [],
        });

        await _pumpEditScreen(tester, event: event, repo: repo);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(repo.lastIsPublic, isNull);
        expect(repo.lastOutside, isNull);
        expect(repo.lastBacklineProvided, isNull);
        expect(repo.lastProductionNeeded, isNull);
      },
    );
  });

  // ── Edit-driven tests ─────────────────────────────────────────────────────

  group('EventEditScreen timeline editing', () {
    testWidgets(
      'removing a timeline entry persists the shorter list on Save',
      (tester) async {
        final repo = _RecordingEventsRepository();
        final event = _makeDetailWithTimeline([
          {'title': 'Load-in', 'time': '2026-04-15 16:00'},
          {'title': 'Soundcheck', 'time': '2026-04-15 17:30'},
        ]);

        await _pumpEditScreen(tester, event: event, repo: repo);

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

        expect(repo.lastTimeline, isNotNull);
        expect(repo.lastTimeline, isEmpty);
      },
    );
  });

  group('EventEditScreen toggle / lodging editing', () {
    testWidgets(
      'flipping the Outdoor switch persists the new value',
      (tester) async {
        final repo = _RecordingEventsRepository();
        final event = _fullyPopulatedEvent();

        await _pumpEditScreen(tester, event: event, repo: repo);

        await _scrollLabelIntoCenter(tester, 'Outdoor');
        // Fixture starts with outside: false. Flip it on.
        await tester.tap(_switchForLabel('Outdoor'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(repo.lastOutside, isTrue);
        expect(repo.lastIsPublic, isTrue);
        expect(repo.lastBacklineProvided, isTrue);
        expect(repo.lastProductionNeeded, isFalse);
      },
    );

    testWidgets(
      'flipping Lodging Provided persists the new checkbox value',
      (tester) async {
        final repo = _RecordingEventsRepository();
        // Start with lodgingProvided: false so the flip moves it to true.
        final event = EventDetail.fromJson({
          'id': 1,
          'key': 'evt-1',
          'title': 'Test Event',
          'date': '2026-04-15',
          'can_write': true,
          'members': [],
          'lodging': [
            {'title': 'Provided', 'type': 'checkbox', 'data': false},
            {'title': 'location', 'type': 'text', 'data': ''},
            {'title': 'check_in', 'type': 'text', 'data': ''},
            {'title': 'check_out', 'type': 'text', 'data': ''},
          ],
        });

        await _pumpEditScreen(tester, event: event, repo: repo);

        await _scrollLabelIntoCenter(tester, 'Lodging Provided');
        await tester.tap(_switchForLabel('Lodging Provided'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(repo.lastLodging, isNotNull);
        final providedRow =
            repo.lastLodging!.firstWhere((r) => r['title'] == 'Provided');
        expect(providedRow['data'], isTrue);
      },
    );
  });

  group('EventEditScreen attire and wedding editing', () {
    testWidgets(
      'editing attire persists the new value',
      (tester) async {
        final repo = _RecordingEventsRepository();
        final event = _fullyPopulatedEvent();

        await _pumpEditScreen(tester, event: event, repo: repo);

        // The attire field starts populated; replace its contents.
        final attireField =
            find.widgetWithText(CupertinoTextField, 'All Black');
        await tester.scrollUntilVisible(
          attireField,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(attireField, 'Cocktail');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(repo.lastAttire, 'Cocktail');
      },
    );

    testWidgets(
      'flipping Ceremony On-site persists the new value',
      (tester) async {
        final repo = _RecordingEventsRepository();
        final event = _fullyPopulatedEvent(); // wedding.onsite: true

        await _pumpEditScreen(tester, event: event, repo: repo);

        await _scrollLabelIntoCenter(tester, 'Ceremony On-site');
        await tester.tap(_switchForLabel('Ceremony On-site'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(repo.lastWedding, isNotNull);
        expect(repo.lastWedding!['onsite'], isFalse);
      },
    );
  });
}
