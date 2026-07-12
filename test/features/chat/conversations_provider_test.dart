import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/providers/conversations_provider.dart';

import '../../helpers/test_harness.dart';

void main() {
  ProviderContainer withConversations(List<Map<String, dynamic>> conversations) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter =
          StubAdapter((_) async => json(200, {'conversations': conversations}));
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('chatConversationsProvider loads the list', () async {
    final c = withConversations([
      {'id': 1, 'type': 'dm', 'title': 'Sam', 'unread_count': 2},
      {'id': 2, 'type': 'band', 'title': 'The Band', 'unread_count': 1},
    ]);
    final list = await c.read(chatConversationsProvider.future);
    expect(list.length, 2);
  });

  test('chatUnreadTotalProvider sums unread counts', () async {
    final c = withConversations([
      {'id': 1, 'type': 'dm', 'title': 'Sam', 'unread_count': 2},
      {'id': 2, 'type': 'band', 'title': 'The Band', 'unread_count': 1},
    ]);
    await c.read(chatConversationsProvider.future);
    expect(c.read(chatUnreadTotalProvider), 3);
  });

  test('chatUnreadTotalProvider is 0 while unloaded', () {
    final c = withConversations([]);
    expect(c.read(chatUnreadTotalProvider), 0);
  });
}
