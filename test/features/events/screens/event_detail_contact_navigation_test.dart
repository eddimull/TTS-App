import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/data/models/conversation.dart';
import 'package:tts_bandmate/features/chat/providers/topic_thread_provider.dart';
import 'package:tts_bandmate/features/contacts/contact_detail_screen.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
import 'package:tts_bandmate/features/events/screens/event_detail_screen.dart';

// Tapping a contact in the event's Contacts section should push the shared
// ContactDetailScreen (the same canonical view used from members/rosters/subs/
// search), not just expose inline tel/mailto links. This guards that wiring.

const _eventKey = 'evt-key';

EventDetail _eventWithContact() => EventDetail.fromJson({
      'id': 1,
      'key': _eventKey,
      'title': 'Wedding Reception',
      'date': '2026-05-20',
      'can_write': false,
      'members': [],
      'contacts': [
        {
          'id': 7,
          'name': 'Claire Hoyt',
          'email': 'clairevhoyt@yahoo.com',
          'phone': '555-123-4567',
          'role': 'Planner',
        },
      ],
    });

// The embedded CommentsSection resolves its topic thread via a provider; stub
// it so the section renders instantly without a network call in this test.
ThreadPage _emptyThread() => (
      conversation: const Conversation(id: 999, type: 'topic', title: ''),
      messages: const [],
      participants: const [],
      channel: '',
      hasMore: false,
    );

void main() {
  testWidgets(
    'tapping an event contact opens the shared ContactDetailScreen',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventDetailProvider(_eventKey).overrideWith(
              (ref) async => _eventWithContact(),
            ),
            topicThreadProvider.overrideWith((ref, topic) => _emptyThread()),
          ],
          child: const CupertinoApp(
            home: EventDetailScreen(eventKey: _eventKey),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The contact appears in the event detail's Contacts section.
      expect(find.text('Claire Hoyt'), findsOneWidget);

      // Tap the contact card (not the inline tel/mailto links).
      await tester.tap(find.text('Claire Hoyt'));
      await tester.pumpAndSettle();

      // The shared detail screen is pushed, showing the contact's info.
      expect(find.byType(ContactDetailScreen), findsOneWidget);
      expect(find.text('clairevhoyt@yahoo.com'), findsOneWidget);

      // Navigating back returns to the event detail.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Claire Hoyt'), findsOneWidget);
    },
  );
}
