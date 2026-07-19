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

  test('successful list fetch fires the bulk delivered ack', () async {
    final captured = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        captured.add(options);
        if (options.path == '/api/mobile/conversations') {
          return json(200, {
            'conversations': [
              {'id': 1, 'type': 'dm', 'title': 'Sam', 'unread_count': 2},
            ],
          });
        }
        return json(204, {});
      });
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);

    await container.read(chatConversationsProvider.future);
    // The ack is fire-and-forget; the stubbed POST crosses more than one
    // microtask turn (like the real HTTP stack would), so pump the event
    // queue to let it land before asserting.
    await pumpEventQueue();

    expect(
      captured.any((o) =>
          o.method == 'POST' &&
          o.path == '/api/mobile/conversations/delivered'),
      isTrue,
    );
  });

  test('failed list fetch does not ack', () async {
    final captured = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        captured.add(options);
        if (options.path == '/api/mobile/conversations') {
          return json(500, {'message': 'nope'});
        }
        return json(204, {});
      });
    final container = ProviderContainer(
      // Riverpod's default retry policy would keep retrying the failing GET
      // (only main.dart's app-wide policy skips retry on a DioException with
      // a response); disable it here so the error surfaces immediately.
      retry: (_, __) => null,
      overrides: [
        chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(chatConversationsProvider.future),
      throwsA(anything),
    );
    await pumpEventQueue();

    expect(
      captured.any((o) => o.path == '/api/mobile/conversations/delivered'),
      isFalse,
    );
  });
}
