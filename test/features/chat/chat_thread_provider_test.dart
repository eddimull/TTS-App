import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/data/models/chat_message.dart';
import 'package:tts_bandmate/features/chat/data/models/chat_participant.dart';
import 'package:tts_bandmate/features/chat/providers/chat_thread_provider.dart';
import 'package:tts_bandmate/features/chat/providers/conversations_provider.dart';
import 'package:tts_bandmate/features/chat/providers/topic_thread_provider.dart';

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
        return null; // test seam: no live subscription, nothing to unbind
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

  test('markRead invalidates both chatConversationsProvider and '
      'topicThreadProvider so a CommentsSection badge on a detail screen '
      'clears once the thread has been read', () async {
    var conversationsCalls = 0;
    var topicCalls = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        if (options.path == '/api/mobile/conversations') {
          conversationsCalls++;
          return json(200, {'conversations': <dynamic>[]});
        }
        if (options.path.endsWith('/conversation')) {
          topicCalls++;
          return json(200, threadJson);
        }
        return json(200, threadJson);
      });
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatTypingTtlProvider.overrideWithValue(Duration.zero),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) {
        capturedHandler = onEvent;
        return null; // test seam: no live subscription, nothing to unbind
      }),
    ]);
    addTearDown(container.dispose);

    const topic = TopicRef(kind: 'events', idOrKey: 'abc123');
    // Seed the topicThreadProvider family member and keep it alive with a
    // listener, mirroring how a CommentsSection on a detail screen watches it.
    final topicSub = container.listen(topicThreadProvider(topic), (_, __) {});
    await container.read(topicThreadProvider(topic).future);
    expect(topicCalls, 1);

    final convSub =
        container.listen(chatConversationsProvider, (_, __) {});
    await container.read(chatConversationsProvider.future);
    expect(conversationsCalls, 1);

    await container.read(chatThreadProvider(5).notifier).load();

    // load() calls markRead() internally once messages are loaded, which
    // should invalidate both families — proven by each refetching once their
    // futures are awaited again.
    await container.read(chatConversationsProvider.future);
    await container.read(topicThreadProvider(topic).future);
    expect(conversationsCalls, 2);
    expect(topicCalls, 2);

    topicSub.close();
    convSub.close();
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

  test('disposing the container mid-flight send does not throw', () async {
    final sendCompleter = Completer<ResponseBody>();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) {
        // The thread page GET and the send POST share the same path;
        // stall only the POST.
        if (options.method == 'POST' &&
            options.path.endsWith('/messages')) {
          return sendCompleter.future;
        }
        return Future.value(json(200, threadJson));
      });
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatTypingTtlProvider.overrideWithValue(Duration.zero),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) {
        capturedHandler = onEvent;
        return null; // test seam: no live subscription, nothing to unbind
      }),
    ]);
    // Hold a listener so autoDispose keeps the notifier alive until we
    // explicitly dispose the container.
    final sub = container.listen(chatThreadProvider(5), (_, __) {});
    final notifier = container.read(chatThreadProvider(5).notifier);
    await notifier.load();

    final pendingSend = notifier.send(text: 'hello');
    sub.close();
    container.dispose();
    sendCompleter.complete(json(200, {
      'message': {
        'id': 9,
        'conversation_id': 5,
        'user_id': 2,
        'user_name': 'Eddie',
        'body': 'hello',
        'created_at': '2026-07-12T14:02:00Z',
      },
    }));
    // Must complete without throwing even though the notifier is gone.
    await pendingSend;
  });

  test('autoDispose unsubscribes the channel and cancels typing timers', () {
    fakeAsync((async) {
      var unsubscribeCalls = 0;
      capturedHandler = null;
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = StubAdapter((_) async => json(200, threadJson));
      final container = ProviderContainer(overrides: [
        chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
        // Long TTL so the typing timer is still armed at dispose time.
        chatTypingTtlProvider.overrideWithValue(const Duration(seconds: 5)),
        chatChannelBinderProvider.overrideWithValue((channel, onEvent) async {
          capturedHandler = onEvent;
          Future<void> unsubscribe() async {
            unsubscribeCalls++;
          }

          return unsubscribe;
        }),
      ]);
      addTearDown(container.dispose);

      final sub = container.listen(chatThreadProvider(5), (_, __) {});
      container.read(chatThreadProvider(5).notifier).load();
      // The stubbed HTTP round-trip crosses the event loop; fire the
      // zero-duration timers until load() completes and binds the channel.
      async.elapse(Duration.zero);
      expect(capturedHandler, isNotNull, reason: 'channel should be bound');

      capturedHandler!('conversation.typing', {'user_id': 3, 'name': 'Sam'});
      expect(container.read(chatThreadProvider(5)).typingUsers, {3: 'Sam'});
      expect(async.pendingTimers, isNotEmpty,
          reason: 'typing TTL timer should be armed');

      // Release the only listener: autoDispose tears the notifier down on
      // the next scheduler tick.
      sub.close();
      async.elapse(Duration.zero);

      expect(unsubscribeCalls, 1,
          reason: 'channel unsubscribe must run on dispose');
      expect(async.pendingTimers, isEmpty,
          reason: 'typing timers must be cancelled on dispose');
    });
  });
}
