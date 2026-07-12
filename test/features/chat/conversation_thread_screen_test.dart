import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/providers/chat_thread_provider.dart';
import 'package:tts_bandmate/features/chat/screens/conversation_thread_screen.dart';
import 'package:dio/dio.dart';

import '../../helpers/test_harness.dart';

void main() {
  testWidgets('renders messages, typing indicator, and deleted tombstone',
      (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async => json(200, {
            'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
            'messages': [
              {
                'id': 1,
                'conversation_id': 5,
                'user_id': 3,
                'user_name': 'Sam',
                'body': 'you around?',
                'created_at': '2026-07-12T14:00:00Z',
              },
              {
                'id': 2,
                'conversation_id': 5,
                'user_id': 3,
                'user_name': 'Sam',
                'body': '',
                'is_deleted': true,
                'created_at': '2026-07-12T14:01:00Z',
              },
            ],
            'participants': [
              {'user_id': 3, 'name': 'Sam', 'last_read_at': null},
            ],
            'channel': 'private-conversation.5',
            'has_more': false,
          }));

    void Function(String, Map<String, dynamic>)? handler;
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) {
        handler = onEvent;
        return null; // test seam: no live subscription, nothing to unbind
      }),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: ConversationThreadScreen(conversationId: 5, title: 'Sam'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('you around?'), findsOneWidget);
    expect(find.text('Message deleted'), findsOneWidget);

    handler!('conversation.typing', {'user_id': 3, 'name': 'Sam'});
    await tester.pump();
    expect(find.text('Sam is typing…'), findsOneWidget);

    // Drain the typing-indicator auto-clear timer (chatTypingTtlProvider's
    // default 5s) before teardown — an unfired Timer trips flutter_test's
    // pending-timer invariant even though the widget tree is being disposed.
    await tester.pump(const Duration(seconds: 5));
  });
}
