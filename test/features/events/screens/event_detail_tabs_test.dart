/// Widget tests for the tabbed event screen: header stays put across tabs,
/// the last tab is remembered, and pasted questionnaire answers fold into a
/// row that opens a sheet where the block can be removed.
library;

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/data/models/conversation.dart';
import 'package:tts_bandmate/features/chat/providers/topic_thread_provider.dart';
import 'package:tts_bandmate/features/events/data/event_music.dart';
import 'package:tts_bandmate/features/events/data/event_tabs.dart';
import 'package:tts_bandmate/features/events/data/events_repository.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/providers/event_music_provider.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
import 'package:tts_bandmate/features/events/screens/event_detail_screen.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';
import 'package:tts_bandmate/features/finances/payout_editor/providers/payout_flow_provider.dart';
import 'package:tts_bandmate/features/media/data/upload_queue_storage.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/eligible_booking.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_instance.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaire_instances_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';

const _key = 'evt-key';

const _pasted = '''Band note up top.

----------
Customer submitted "Wedding Day Questionnaire" on Oct 20
== Bride and Groom Information ==
Bride / Groom: Grace Terreson
Venue name: Il Mercato
== First Dances ==
First dance: Forever and Ever, Amen''';

EventDetail _event(
        {String? notes,
        bool canWrite = true,
        bool timeline = true,
        bool music = false}) =>
    EventDetail.fromJson({
      'id': 1,
      'key': _key,
      'title': 'Terreson Wedding',
      'date': '2026-11-07',
      'time': '16:30',
      'end_time': '23:00',
      'venue_name': 'Il Mercato',
      'can_write': canWrite,
      'eventable_type': 'Bookings',
      'eventable_id': 9,
      'notes': notes,
      if (music)
        'performance': {
          'notes': 'Upbeat only',
          'songs': <dynamic>[],
          'charts': <dynamic>[],
        },
      'members': <dynamic>[],
      'timeline': timeline
          ? [
              {'title': 'Load in', 'time': '2026-11-07 14:30'},
              {'title': 'Show', 'time': '2026-11-07 16:30'},
            ]
          : <dynamic>[],
    });

ThreadPage _emptyThread() => (
      conversation: const Conversation(id: 1, type: 'topic', title: ''),
      messages: const [],
      participants: const [],
      channel: '',
      hasMore: false,
    );

class _FakeDetail extends EventDetailNotifier {
  _FakeDetail(this._value) : super(_key);
  final EventDetail _value;
  @override
  Future<EventDetail> build() async => _value;
}

class _FakeBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _RecordingRepo extends EventsRepository {
  _RecordingRepo() : super(Dio());
  final savedNotes = <String?>[];

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
    Map<String, dynamic>? wedding,
  }) async {
    savedNotes.add(notes);
  }
}

class _FakeInvalidator extends Fake implements CacheInvalidator {
  final changed = <String>[];
  @override
  void onEventChanged({required String eventKey}) => changed.add(eventKey);
}

Future<void> _pump(
  WidgetTester tester,
  EventDetail event, {
  Map<String, Object> prefs = const {},
  _RecordingRepo? repo,
  _FakeInvalidator? invalidator,
  List<QuestionnaireInstance> questionnaires = const [],
  EventMusic? music,
  bool owner = false,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eventDetailProvider(_key).overrideWith(() => _FakeDetail(event)),
        topicThreadProvider.overrideWith((ref, topic) => _emptyThread()),
        uploadQueueStorageProvider.overrideWithValue(UploadQueueStorage(sp)),
        if (repo != null) eventsRepositoryProvider.overrideWithValue(repo),
        if (invalidator != null)
          cacheInvalidatorProvider.overrideWithValue(invalidator),
        selectedBandProvider.overrideWith(_FakeBand.new),
        bookingQuestionnairesProvider.overrideWith((ref, args) async =>
            BookingQuestionnaires(instances: questionnaires)),
        eventMusicProvider.overrideWith((ref, key) async => music),
        isSelectedBandOwnerProvider.overrideWithValue(owner),
      ],
      child: const CupertinoApp(home: EventDetailScreen(eventKey: _key)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _tabBar => find.byType(CupertinoSlidingSegmentedControl<EventTab>);

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: _tabBar, matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  group('header', () {
    testWidgets('shows date and Load-in / Show / End tiles', (tester) async {
      await _pump(tester, _event());
      expect(find.text('Sat, Nov 7'), findsOneWidget);
      expect(find.text('Load-in'), findsOneWidget);
      expect(find.text('2:30 PM'), findsOneWidget);
      expect(find.text('4:30 PM'), findsWidgets);
      expect(find.text('11:00 PM'), findsOneWidget);
    });

    testWidgets('missing times show a dash', (tester) async {
      final e = EventDetail.fromJson({
        'id': 1,
        'key': _key,
        'title': 'T',
        'date': '2026-11-07',
        'can_write': true,
        'members': <dynamic>[],
      });
      await _pump(tester, e);
      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('switching tabs does not move the tab bar', (tester) async {
      await _pump(tester, _event(notes: 'Some notes'));
      final before = tester.getTopLeft(_tabBar);
      await _openTab(tester, 'Notes');
      expect(tester.getTopLeft(_tabBar), before);
      await _openTab(tester, 'Timeline');
      expect(tester.getTopLeft(_tabBar), before);
    });

    testWidgets('collapses to a one-line summary after scrolling',
        (tester) async {
      await _pump(tester, _event(notes: List.filled(60, 'line').join('\n')));
      await _openTab(tester, 'Notes');
      expect(
          find.text('Sat, Nov 7 · Show 4:30 PM · Il Mercato'), findsOneWidget);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
      await tester.pumpAndSettle();

      // The tab bar is still pinned directly under the collapsed summary.
      final top = tester.getTopLeft(_tabBar).dy;
      final summary = tester
          .getTopLeft(find.text('Sat, Nov 7 · Show 4:30 PM · Il Mercato'))
          .dy;
      expect(summary, lessThan(top));
      expect(tester.getTopLeft(find.byType(CustomScrollView)).dy,
          lessThan(summary));
    });
  });

  group('tabs', () {
    testWidgets('opens on Overview by default', (tester) async {
      await _pump(tester, _event());
      expect(find.text('Band notes'), findsNothing);
    });

    testWidgets('opens on the remembered tab', (tester) async {
      await _pump(tester, _event(notes: 'Hello'),
          prefs: {'event_last_tab': 'notes'});
      expect(find.text('Band notes'), findsOneWidget);
    });

    testWidgets('falls back to Overview when the remembered tab is hidden',
        (tester) async {
      await _pump(tester, _event(timeline: false),
          prefs: {'event_last_tab': 'timeline'});
      expect(find.text('Band notes'), findsNothing);
      expect(find.descendant(of: _tabBar, matching: find.text('Timeline')),
          findsNothing);
    });

    testWidgets('picking a tab stores it', (tester) async {
      await _pump(tester, _event());
      await _openTab(tester, 'Notes');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('event_last_tab'), 'notes');
    });

    testWidgets('discussion bar stays on every tab', (tester) async {
      await _pump(tester, _event());
      expect(find.text('Add a comment…'), findsOneWidget);
      await _openTab(tester, 'Notes');
      expect(find.text('Add a comment…'), findsOneWidget);
    });
  });

  group('Notes tab', () {
    testWidgets('pasted answers fold into one row, band notes stay visible',
        (tester) async {
      await _pump(tester, _event(notes: _pasted),
          prefs: {'event_last_tab': 'notes'});

      expect(find.text('Band note up top.'), findsOneWidget);
      expect(find.text('Wedding Day Questionnaire'), findsOneWidget);
      expect(find.text('Pasted answers · Oct 20 · 3 answers'), findsOneWidget);
      // Answers themselves are not dumped into the page.
      expect(find.textContaining('Grace Terreson'), findsNothing);
    });

    testWidgets('row opens a sheet with collapsible sections', (tester) async {
      await _pump(tester, _event(notes: _pasted),
          prefs: {'event_last_tab': 'notes'});
      await tester.tap(find.text('Wedding Day Questionnaire'));
      await tester.pumpAndSettle();

      expect(find.text('Client answers'), findsOneWidget);
      expect(find.text('Bride and Groom Information'), findsOneWidget);
      expect(find.text('First Dances'), findsOneWidget);
      // Collapsed until tapped.
      expect(find.text('Grace Terreson'), findsNothing);

      await tester.tap(find.text('Bride and Groom Information'));
      await tester.pumpAndSettle();
      expect(find.text('Grace Terreson'), findsOneWidget);
    });

    testWidgets('remove asks to confirm, then saves notes without the block',
        (tester) async {
      final repo = _RecordingRepo();
      final inv = _FakeInvalidator();
      await _pump(tester, _event(notes: _pasted),
          prefs: {'event_last_tab': 'notes'}, repo: repo, invalidator: inv);
      await tester.tap(find.text('Wedding Day Questionnaire'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Remove pasted text from notes'));
      await tester.tap(find.text('Remove pasted text from notes'));
      await tester.pumpAndSettle();
      expect(find.text('Remove pasted text?'), findsOneWidget);
      expect(repo.savedNotes, isEmpty);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(repo.savedNotes, ['Band note up top.']);
      expect(inv.changed, [_key]);
      // Sheet closed.
      expect(find.text('Client answers'), findsNothing);
    });

    testWidgets('cancelling the confirm saves nothing', (tester) async {
      final repo = _RecordingRepo();
      await _pump(tester, _event(notes: _pasted),
          prefs: {'event_last_tab': 'notes'}, repo: repo);
      await tester.tap(find.text('Wedding Day Questionnaire'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remove pasted text from notes'));
      await tester.tap(find.text('Remove pasted text from notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.savedNotes, isEmpty);
      expect(find.text('Client answers'), findsOneWidget);
    });

    testWidgets('read-only viewers do not get the remove action',
        (tester) async {
      await _pump(tester, _event(notes: _pasted, canWrite: false),
          prefs: {'event_last_tab': 'notes'});
      await tester.tap(find.text('Wedding Day Questionnaire'));
      await tester.pumpAndSettle();
      expect(find.text('Remove pasted text from notes'), findsNothing);
    });

    testWidgets('booking event with no questionnaire shows the empty state',
        (tester) async {
      await _pump(tester, _event(notes: 'Just a note'),
          prefs: {'event_last_tab': 'notes'});
      expect(find.text('No questionnaire answers yet'), findsOneWidget);
      expect(find.textContaining('Send'), findsNothing);
    });

    testWidgets('angle brackets in notes survive (decoded only once)',
        (tester) async {
      await _pump(tester, _event(notes: 'Wear &lt;red&gt; ties'),
          prefs: {'event_last_tab': 'notes'});
      expect(find.text('Wear <red> ties'), findsOneWidget);
    });

    testWidgets('tabs stay mounted offstage when switching', (tester) async {
      await _pump(tester, _event(notes: 'Hello'),
          prefs: {'event_last_tab': 'notes'});
      await _openTab(tester, 'Overview');
      expect(find.text('Hello', skipOffstage: false), findsOneWidget);
      expect(find.text('Hello'), findsNothing);
    });

    testWidgets('notes that are only pasted answers do not read as empty',
        (tester) async {
      final onlyPasted = _pasted.substring(_pasted.indexOf('----------'));
      await _pump(tester, _event(notes: onlyPasted),
          prefs: {'event_last_tab': 'notes'});
      expect(find.text('No band notes yet'), findsNothing);
      expect(find.text('Wedding Day Questionnaire'), findsOneWidget);
    });

    testWidgets(
        'the booking questionnaire stays listed after its pasted copy is removed',
        (tester) async {
      final submitted = QuestionnaireInstance.fromJson({
        'id': 3,
        'name': 'Wedding Day Questionnaire',
        'status': 'submitted',
        'recipient_name': 'Grace Terreson',
        'submitted_at': '2026-10-20T15:00:00Z',
        'questionnaire_id': 7,
        'booking': {'id': 9, 'name': 'Terreson Wedding'},
      });
      await _pump(tester, _event(notes: 'Just a note'),
          prefs: {'event_last_tab': 'notes'}, questionnaires: [submitted]);
      expect(find.text('Wedding Day Questionnaire'), findsOneWidget);
      expect(find.textContaining('Grace Terreson'), findsOneWidget);
      expect(find.text('No questionnaire answers yet'), findsNothing);
    });
  });

  group('Music tab', () {
    final music = EventMusic(
      bandSongs: [
        for (var i = 1; i <= 8; i++) BandSongSummary(id: i, title: 'Song $i'),
      ],
      requests: const ClientSongRequests(
        mustPlayIds: {1, 2, 3, 4, 5, 6, 7},
        doNotPlayIds: {8},
      ),
      setlist: const EventSetlist(id: 1, status: 'ready', songs: [
        SetlistEntry(type: 'song', position: 1, songId: 1, title: 'Song 1'),
        SetlistEntry(
            type: 'song',
            position: 2,
            customTitle: 'Here for a Good Time',
            customArtist: 'George Strait'),
        SetlistEntry(
            type: 'song', position: 3, customTitle: 'Boogie Wonderland'),
        SetlistEntry(type: 'song', position: 4, customTitle: 'Third New'),
      ]),
    );

    testWidgets('summary counts songs, to learn and requests', (tester) async {
      await _pump(tester, _event(music: true),
          music: music, prefs: {'event_last_tab': 'music'});
      expect(find.text('Performance notes'), findsOneWidget);
      expect(find.text('Upbeat only'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // songs
      expect(find.text('3'), findsOneWidget); // to learn
      expect(find.text('7'), findsOneWidget); // must-play requests
      expect(find.text('Not in our catalog'), findsOneWidget);
      expect(find.text('Here for a Good Time · George Strait'), findsOneWidget);
      expect(find.text('Boogie Wonderland'), findsOneWidget);
      expect(find.text('Third New'), findsNothing);
      expect(find.text('+ 1 more'), findsOneWidget);
      expect(find.text('Open music'), findsOneWidget);
    });

    testWidgets('picks alone show the Music tab', (tester) async {
      await _pump(tester, _event(),
          music: const EventMusic(
            bandSongs: [BandSongSummary(id: 1, title: 'Song 1')],
            requests: ClientSongRequests(mustPlayIds: {1}, doNotPlayIds: {}),
          ));
      expect(find.descendant(of: _tabBar, matching: find.text('Music')),
          findsOneWidget);
    });

    testWidgets('setlist songs alone show the Music tab', (tester) async {
      await _pump(tester, _event(),
          music: const EventMusic(setlist: EventSetlist(id: 1, status: 'draft', songs: [
            SetlistEntry(type: 'song', position: 1, songId: 1),
          ])));
      expect(find.descendant(of: _tabBar, matching: find.text('Music')),
          findsOneWidget);
    });

    testWidgets('an empty setlist and no picks hide the Music tab',
        (tester) async {
      await _pump(tester, _event(), music: const EventMusic());
      expect(find.descendant(of: _tabBar, matching: find.text('Music')),
          findsNothing);
    });

    testWidgets('Run the live setlist confirms away from gig day',
        (tester) async {
      await _pump(tester, _event(music: true),
          prefs: {'event_last_tab': 'music'});
      await tester.ensureVisible(find.text('Run the live setlist'));
      await tester.tap(find.text('Run the live setlist'));
      await tester.pumpAndSettle();
      expect(find.text('Not gig day'), findsOneWidget);
    });

    testWidgets('read-only members get no Run button', (tester) async {
      await _pump(tester, _event(music: true, canWrite: false),
          prefs: {'event_last_tab': 'music'});
      expect(find.text('Run the live setlist'), findsNothing);
    });
  });

  group('send questionnaire from the event', () {
    testWidgets('owners get a send row when nothing was sent yet',
        (tester) async {
      await _pump(tester, _event(notes: 'Just a note'),
          prefs: {'event_last_tab': 'notes'}, owner: true);
      expect(find.text('No questionnaire answers yet'), findsOneWidget);
      expect(find.text('Send questionnaire'), findsOneWidget);
    });

    testWidgets('owners can send another once one exists', (tester) async {
      final sent = QuestionnaireInstance.fromJson({
        'id': 3,
        'name': 'Wedding Day Questionnaire',
        'status': 'sent',
        'recipient_name': 'Grace Terreson',
        'questionnaire_id': 7,
        'booking': {'id': 9, 'name': 'Terreson Wedding'},
      });
      await _pump(tester, _event(notes: 'Just a note'),
          prefs: {'event_last_tab': 'notes'},
          owner: true,
          questionnaires: [sent]);
      expect(find.text('Send another questionnaire'), findsOneWidget);
    });

    testWidgets('members do not get the send row', (tester) async {
      await _pump(tester, _event(notes: 'Just a note'),
          prefs: {'event_last_tab': 'notes'});
      expect(find.textContaining('Send'), findsNothing);
    });

    testWidgets('owners get Send questionnaire in the menu', (tester) async {
      await _pump(tester, _event(), owner: true);
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis_circle));
      await tester.pumpAndSettle();
      expect(find.text('Send questionnaire'), findsOneWidget);
    });
  });
}
