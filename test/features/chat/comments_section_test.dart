import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/widgets/comments_section.dart';

import '../../helpers/test_harness.dart';

void main() {
  Dio dioReturning(Map<String, dynamic> body) =>
      Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = StubAdapter((_) async => json(200, body));

  testWidgets('shows recent comments and the view-all row', (tester) async {
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dioReturning({
        'conversation': {
          'id': 5,
          'type': 'topic',
          'title': 'Gig at Blue Room',
          'unread_count': 2,
        },
        'messages': [
          {
            'id': 1,
            'conversation_id': 5,
            'user_id': 2,
            'user_name': 'Eddie',
            'body': 'sound check at 6',
            'created_at': '2026-07-12T14:00:00Z',
          },
        ],
        'participants': [],
        'channel': 'private-conversation.5',
        'has_more': false,
      }))),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: ListView(
            children: [CommentsSection(kind: 'events', idOrKey: 'abc123')],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Comments'), findsOneWidget);
    // RichText doesn't show up in find.text(), so we verify by checking
    // that the View all button shows the correct total count (1) and unread (2)
    expect(find.text('View all (1) · 2 unread'), findsOneWidget);
  });

  test('TopicRef is value-equal (family cache key)', () {
    expect(const TopicRef(kind: 'events', idOrKey: 'a'),
        const TopicRef(kind: 'events', idOrKey: 'a'));
    expect(
        const TopicRef(kind: 'events', idOrKey: 'a').hashCode,
        const TopicRef(kind: 'events', idOrKey: 'a').hashCode);
  });
}
