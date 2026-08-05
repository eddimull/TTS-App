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

      // Lodging row present with the stay's name.
      expect(find.text('Grand Hotel'), findsOneWidget);
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
}

class _FakeSelectedBand extends SelectedBandNotifier {
  _FakeSelectedBand(this._id);
  final int _id;

  @override
  Future<int?> build() async => _id;
}
