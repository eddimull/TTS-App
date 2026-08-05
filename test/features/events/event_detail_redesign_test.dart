import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/data/models/conversation.dart';
import 'package:tts_bandmate/features/chat/providers/topic_thread_provider.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
import 'package:tts_bandmate/features/events/screens/event_detail_screen.dart';
import 'package:tts_bandmate/features/media/data/upload_queue_storage.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

// Task 3 of the lodging-adjustments event-detail redesign: nav overflow
// menu, status dot, single-line chips, and the at-a-glance card. These tests
// pump the real screen with a stubbed eventDetailProvider (following the
// scaffolding pattern from event_detail_contact_navigation_test.dart) and
// assert against the new nav/menu/glance-card surface.

const _eventKey = 'evt-key';

EventDetail _baseEvent({
  bool canWrite = true,
  String? status = 'confirmed',
  String? eventableType,
  int? eventableId,
  String? attire,
  String? time = '19:30',
  String? endTime = '22:00',
  List<Map<String, dynamic>> lodgings = const [],
}) =>
    EventDetail.fromJson({
      'id': 1,
      'key': _eventKey,
      'title': 'Summer Gala',
      'date': '2026-05-20',
      'time': time,
      'end_time': endTime,
      'can_write': canWrite,
      'status': status,
      'eventable_type': eventableType,
      'eventable_id': eventableId,
      'attire': attire,
      'members': [],
      'lodgings': lodgings,
    });

// The embedded CommentBar resolves its topic thread via a provider; stub it
// so sections render instantly without a network call in these tests.
ThreadPage _emptyThread() => (
      conversation: const Conversation(id: 999, type: 'topic', title: ''),
      messages: const [],
      participants: const [],
      channel: '',
      hasMore: false,
    );

Future<void> _pump(
  WidgetTester tester,
  EventDetail event, {
  int? selectedBandId,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // canWrite:true renders _MediaSection, which reads the upload queue —
  // give it a real (mock-backed) storage so it doesn't hit the
  // "must be overridden in main()" placeholder provider.
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eventDetailProvider(_eventKey).overrideWith((ref) async => event),
        topicThreadProvider.overrideWith((ref, topic) => _emptyThread()),
        uploadQueueStorageProvider.overrideWithValue(UploadQueueStorage(prefs)),
        if (selectedBandId != null)
          selectedBandProvider.overrideWith(() => _FakeSelectedBand(selectedBandId)),
      ],
      child: const CupertinoApp(
        home: EventDetailScreen(eventKey: _eventKey),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('overflow menu', () {
    testWidgets(
        'shows booking, roster, setlist actions and edit only when canWrite',
        (tester) async {
      final event = _baseEvent(
        canWrite: true,
        eventableType: 'Bookings',
        eventableId: 42,
      );
      await _pump(tester, event, selectedBandId: 7);

      await tester.tap(find.byIcon(CupertinoIcons.ellipsis_circle));
      await tester.pumpAndSettle();

      final sheet = find.byType(CupertinoActionSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text('Go to booking')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Go to roster')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Setlist')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Edit event')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Cancel')),
        findsOneWidget,
      );
    });

    testWidgets('hides Edit event when canWrite is false', (tester) async {
      final event = _baseEvent(canWrite: false);
      await _pump(tester, event);

      await tester.tap(find.byIcon(CupertinoIcons.ellipsis_circle));
      await tester.pumpAndSettle();

      expect(find.text('Edit event'), findsNothing);
    });

    testWidgets('hides Go to booking when the event is not booking-backed',
        (tester) async {
      final event = _baseEvent(canWrite: false, eventableType: null);
      await _pump(tester, event);

      await tester.tap(find.byIcon(CupertinoIcons.ellipsis_circle));
      await tester.pumpAndSettle();

      expect(find.text('Go to booking'), findsNothing);
    });
  });

  group('status dot', () {
    testWidgets('renders as a dot, not a labeled row', (tester) async {
      final event = _baseEvent(status: 'confirmed');
      await _pump(tester, event);

      expect(find.text('Status'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('Status: confirmed')),
        findsOneWidget,
      );
    });

    testWidgets('renders no dot when status is null', (tester) async {
      final event = _baseEvent(status: null);
      await _pump(tester, event);

      expect(find.bySemanticsLabel(RegExp('^Status: ')), findsNothing);
    });
  });

  group('at-a-glance card', () {
    testWidgets('shows show time, attire expands inline, lodging navigates',
        (tester) async {
      final event = _baseEvent(
        time: '19:30',
        endTime: '22:00',
        attire: 'Black tie',
        lodgings: [
          {
            'id': 5,
            'name': 'Grand Hotel',
            'check_in_at': '2026-05-20T15:00:00',
            'check_out_at': '2026-05-21T11:00:00',
          },
        ],
      );
      await _pump(tester, event);

      // Show time row.
      expect(find.textContaining('Show'), findsWidgets);
      expect(find.textContaining('7:30'), findsWidgets);
      expect(find.textContaining('ends'), findsWidgets);

      // Attire collapsed by default.
      expect(find.text('Black tie'), findsNothing);
      expect(find.text('Attire'), findsOneWidget);

      await tester.tap(find.text('Attire'));
      await tester.pumpAndSettle();

      expect(find.text('Black tie'), findsOneWidget);

      // Lodging row present with the stay's name. Task 4's reorder keeps
      // both the glance card's summary row AND the full Lodging section
      // visible in the same body, so the name legitimately appears twice.
      expect(find.text('Grand Hotel'), findsWidgets);
    });

    testWidgets('card is hidden entirely when there is no glance data',
        (tester) async {
      final event = _baseEvent(
        time: null,
        endTime: null,
        attire: null,
        lodgings: const [],
      );
      await _pump(tester, event);

      expect(find.text('Attire'), findsNothing);
      expect(find.textContaining('Show'), findsNothing);
    });
  });

  group('flags row', () {
    testWidgets('chips render in a horizontally scrollable single line',
        (tester) async {
      final event = EventDetail.fromJson({
        'id': 1,
        'key': _eventKey,
        'title': 'Summer Gala',
        'date': '2026-05-20',
        'can_write': true,
        'members': [],
        'is_public': true,
        'outside': true,
        'backline_provided': true,
        'production_needed': true,
      });
      await _pump(tester, event);

      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Outdoor'), findsOneWidget);
      expect(find.text('Backline'), findsOneWidget);
      expect(find.text('Production'), findsOneWidget);
    });
  });

  // Task 4: bundle Notes + Attachments into one section, and reorder the
  // body logistics-first: glance card → Notes(+attachments) → Timeline →
  // Lodging → Contacts → Roster → Performance → Wedding → Media.
  group('notes+attachments bundle', () {
    testWidgets('long note is clamped with a Show more/less toggle',
        (tester) async {
      final longNote = List.generate(20, (i) => 'Line $i of notes text here')
          .join('\n');
      final event = _baseEvent().copyWithNotes(longNote);
      await _pump(tester, event);

      expect(find.text('Show more'), findsOneWidget);
      expect(find.text('Show less'), findsNothing);

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();

      expect(find.text('Show less'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
    });

    testWidgets('short note has no toggle', (tester) async {
      final event = _baseEvent().copyWithNotes('Short note, one line.');
      await _pump(tester, event);

      expect(find.text('Show more'), findsNothing);
      expect(find.text('Show less'), findsNothing);
      expect(find.text('Short note, one line.'), findsOneWidget);
    });

    testWidgets('attachments capped at 3 rows with a Show all (N) toggle',
        (tester) async {
      final event = _baseEvent().copyWithAttachments([
        for (int i = 1; i <= 5; i++)
          {
            'id': i,
            'filename': 'file_$i.pdf',
            'mime_type': 'application/pdf',
            'file_size': 1024,
          },
      ]);
      await _pump(tester, event);

      for (int i = 1; i <= 3; i++) {
        expect(find.text('file_$i.pdf'), findsOneWidget);
      }
      expect(find.text('file_4.pdf'), findsNothing);
      expect(find.text('file_5.pdf'), findsNothing);
      expect(find.text('Show all (5)'), findsOneWidget);

      await tester.tap(find.text('Show all (5)'));
      await tester.pumpAndSettle();

      for (int i = 1; i <= 5; i++) {
        expect(find.text('file_$i.pdf'), findsOneWidget);
      }
    });

    testWidgets('Notes header renders once for the combined section',
        (tester) async {
      final event = _baseEvent()
          .copyWithNotes('Some notes')
          .copyWithAttachments([
        {
          'id': 1,
          'filename': 'file_1.pdf',
          'mime_type': 'application/pdf',
          'file_size': 1024,
        },
      ]);
      await _pump(tester, event);

      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Attachments'), findsNothing);
    });
  });

  group('body section order', () {
    testWidgets('Notes appears above Timeline', (tester) async {
      final event = _baseEvent().copyWithNotes('Some notes').copyWithTimeline([
        {'title': 'Load in', 'time': '18:00'},
      ]);
      await _pump(tester, event);

      final notesTop = tester.getTopLeft(find.text('Notes')).dy;
      final timelineTop = tester.getTopLeft(find.text('Timeline')).dy;

      expect(notesTop, lessThan(timelineTop));
    });

    testWidgets('Attire section header findsNothing (attire lives in glance card)',
        (tester) async {
      final event = _baseEvent(attire: 'Black tie');
      await _pump(tester, event);

      expect(find.text('Attire'), findsOneWidget); // glance card row label
      // No standalone card-style _SectionHeader titled "Attire".
      final headers = find.text('Attire');
      expect(tester.widgetList(headers).length, 1);
    });

    testWidgets('plain Setlist row absent from body', (tester) async {
      final event = _baseEvent();
      await _pump(tester, event);

      expect(find.text('Setlist'), findsNothing);
    });

    testWidgets('Join Live Setlist button stays in body when live session active',
        (tester) async {
      final event = _baseEvent().copyWithLiveSession(42);
      await _pump(tester, event);

      expect(find.text('Join Live Setlist'), findsOneWidget);
    });
  });
}

extension _EventDetailTestExtensions on EventDetail {
  EventDetail copyWithNotes(String notes) => EventDetail.fromJson({
        ..._toJsonForTest(this),
        'notes': notes,
      });

  EventDetail copyWithAttachments(List<Map<String, dynamic>> attachments) =>
      EventDetail.fromJson({
        ..._toJsonForTest(this),
        'attachments': attachments,
      });

  EventDetail copyWithTimeline(List<Map<String, dynamic>> timeline) =>
      EventDetail.fromJson({
        ..._toJsonForTest(this),
        'timeline': timeline,
      });

  EventDetail copyWithLiveSession(int liveSessionId) => EventDetail.fromJson({
        ..._toJsonForTest(this),
        'live_session_id': liveSessionId,
      });
}

// Rebuilds a minimal JSON map carrying forward the fields the fixtures in
// this file set, so the copyWith* helpers above can layer one extra field
// on without re-deriving the whole payload. Only fields exercised by these
// tests need round-tripping.
Map<String, dynamic> _toJsonForTest(EventDetail event) => {
      'id': event.id,
      'key': event.key,
      'title': event.title,
      'date': event.date,
      'time': event.time,
      'end_time': event.endTime,
      'can_write': event.canWrite,
      'status': event.status,
      'eventable_type': event.eventableType,
      'eventable_id': event.eventableId,
      'attire': event.attire,
      'members': const [],
      'lodgings': const [],
      'notes': event.notes,
      'live_session_id': event.liveSessionId,
    };

class _FakeSelectedBand extends SelectedBandNotifier {
  _FakeSelectedBand(this._id);
  final int _id;

  @override
  Future<int?> build() async => _id;
}
