import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/data/models/chat_message.dart';
import 'package:tts_bandmate/features/chat/data/models/chat_participant.dart';
import 'package:tts_bandmate/features/chat/providers/chat_thread_provider.dart';

import '../../helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final threadJson = {
    'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
    'messages': [
      {
        'id': 1,
        'conversation_id': 5,
        'user_id': 2,
        'user_name': 'Eddie',
        'body': 'hey',
        'created_at': '2026-07-12T14:00:00Z',
      },
    ],
    'participants': [
      {'user_id': 2, 'name': 'Eddie', 'last_read_at': '2026-07-12T14:00:00Z'},
      {'user_id': 3, 'name': 'Sam', 'last_read_at': null},
    ],
    'channel': 'private-conversation.5',
    'has_more': false,
  };

  late List<String> boundChannels;
  late void Function(String, Map<String, dynamic>)? capturedHandler;

  ProviderContainer makeContainer() {
    boundChannels = [];
    capturedHandler = null;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async => json(200, threadJson));
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatTypingTtlProvider.overrideWithValue(Duration.zero),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) {
        boundChannels.add(channel);
        capturedHandler = onEvent;
      }),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('load fetches the page and binds the live channel', () async {
    final c = makeContainer();
    await c.read(chatThreadProvider(5).notifier).load();
    final state = c.read(chatThreadProvider(5));
    expect(state.messages.single.body, 'hey');
    expect(state.participants.length, 2);
    expect(boundChannels, ['private-conversation.5']);
  });

  test('message.created appends; message.deleted tombstones', () async {
    final c = makeContainer();
    await c.read(chatThreadProvider(5).notifier).load();

    capturedHandler!('message.created', {
      'message': {
        'id': 2,
        'conversation_id': 5,
        'user_id': 3,
        'user_name': 'Sam',
        'body': 'yo',
        'created_at': '2026-07-12T14:01:00Z',
      },
    });
    expect(c.read(chatThreadProvider(5)).messages.length, 2);

    capturedHandler!('message.deleted', {'message_id': 2});
    final state = c.read(chatThreadProvider(5));
    expect(state.messages.length, 2);
    expect(state.messages.last.isDeleted, isTrue);
  });

  test('duplicate message.created (own send echo) is ignored', () async {
    final c = makeContainer();
    await c.read(chatThreadProvider(5).notifier).load();
    final echo = {
      'message': {
        'id': 1,
        'conversation_id': 5,
        'user_id': 2,
        'user_name': 'Eddie',
        'body': 'hey',
        'created_at': '2026-07-12T14:00:00Z',
      },
    };
    capturedHandler!('message.created', echo);
    expect(c.read(chatThreadProvider(5)).messages.length, 1);
  });

  test('conversation.read updates participant lastReadAt', () async {
    final c = makeContainer();
    await c.read(chatThreadProvider(5).notifier).load();
    capturedHandler!('conversation.read',
        {'user_id': 3, 'last_read_at': '2026-07-12T14:05:00Z'});
    final sam = c
        .read(chatThreadProvider(5))
        .participants
        .firstWhere((p) => p.userId == 3);
    expect(sam.lastReadAt, isNotNull);
  });

  test('conversation.typing adds then expires a typing user', () async {
    final c = makeContainer();
    await c.read(chatThreadProvider(5).notifier).load();
    capturedHandler!('conversation.typing', {'user_id': 3, 'name': 'Sam'});
    expect(c.read(chatThreadProvider(5)).typingUsers, {3: 'Sam'});
    // TTL is zero in tests: a timer tick clears it.
    await Future<void>.delayed(Duration.zero);
    expect(c.read(chatThreadProvider(5)).typingUsers, isEmpty);
  });

  test('seenByOthersCount counts other participants who read past the message',
      () {
    final msg = ChatMessage(
      id: 1,
      conversationId: 5,
      userId: 2,
      userName: 'Eddie',
      body: 'hey',
      createdAt: DateTime.utc(2026, 7, 12, 14),
    );
    final participants = [
      ChatParticipant(
          userId: 2, name: 'Eddie', lastReadAt: DateTime.utc(2026, 7, 12, 15)),
      ChatParticipant(
          userId: 3, name: 'Sam', lastReadAt: DateTime.utc(2026, 7, 12, 14, 30)),
      const ChatParticipant(userId: 4, name: 'Lee'),
    ];
    expect(seenByOthersCount(msg, participants, 2), 1);
  });
}
