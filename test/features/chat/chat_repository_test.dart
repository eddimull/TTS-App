import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';

import '../../helpers/test_harness.dart';

void main() {
  Dio dioReturning(Map<String, dynamic> body) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async => json(200, body));
    return dio;
  }

  final threadJson = {
    'conversation': {'id': 5, 'type': 'topic', 'title': 'Gig at Blue Room'},
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
    'participants': [
      {'user_id': 2, 'name': 'Eddie', 'last_read_at': '2026-07-12T14:00:00Z'},
    ],
    'channel': 'private-conversation.5',
    'has_more': false,
  };

  test('listConversations parses list', () async {
    final repo = ChatRepository(dioReturning({
      'conversations': [
        {'id': 5, 'type': 'band', 'title': 'The Band', 'unread_count': 2},
      ],
    }));
    final list = await repo.listConversations();
    expect(list.single.id, 5);
    expect(list.single.unreadCount, 2);
  });

  test('openDm parses conversation', () async {
    final repo = ChatRepository(dioReturning({
      'conversation': {'id': 9, 'type': 'dm', 'title': 'Sam'},
    }));
    final c = await repo.openDm(3);
    expect(c.id, 9);
    expect(c.type, 'dm');
  });

  test('topicThread and messages parse a ThreadPage', () async {
    final repo = ChatRepository(dioReturning(threadJson));
    final page = await repo.topicThread(kind: 'events', idOrKey: 'abc123');
    expect(page.conversation.id, 5);
    expect(page.messages.single.body, 'sound check at 6');
    expect(page.participants.single.userId, 2);
    expect(page.channel, 'private-conversation.5');
    expect(page.hasMore, isFalse);

    final page2 = await repo.messages(5, beforeId: 100);
    expect(page2.conversation.id, 5);
  });

  test('sendMessage and editMessage parse the message envelope', () async {
    final repo = ChatRepository(dioReturning({
      'message': {
        'id': 2,
        'conversation_id': 5,
        'user_id': 2,
        'user_name': 'Eddie',
        'body': 'hi',
        'created_at': '2026-07-12T15:00:00Z',
      },
    }));
    final sent = await repo.sendMessage(5, body: 'hi');
    expect(sent.id, 2);
    final edited = await repo.editMessage(2, 'hi!');
    expect(edited.id, 2);
  });

  test('attachmentUrl is absolute', () {
    final repo = ChatRepository(Dio(BaseOptions(baseUrl: 'http://test.local')));
    expect(repo.attachmentUrl(2, 7),
        'http://test.local/api/mobile/messages/2/attachments/7');
  });
}
