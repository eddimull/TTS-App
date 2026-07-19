import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/data/models/chat_message.dart';
import 'package:tts_bandmate/features/chat/data/models/chat_participant.dart';
import 'package:tts_bandmate/features/chat/providers/chat_thread_provider.dart';
import 'package:tts_bandmate/features/chat/providers/conversations_provider.dart';
import 'package:tts_bandmate/features/chat/providers/topic_thread_provider.dart';

import '../../helpers/test_harness.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._state);
  final AuthState _state;

  @override
  Future<AuthState> build() async => _state;
}

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
  late int readPostCount;

  ProviderContainer makeContainer({
    AuthState? authState,
    Duration markReadDebounce = Duration.zero,
  }) {
    boundChannels = [];
    capturedHandler = null;
    readPostCount = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        if (options.method == 'POST' && options.path.endsWith('/read')) {
          readPostCount++;
        }
        return json(200, threadJson);
      });
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatTypingTtlProvider.overrideWithValue(Duration.zero),
      chatMarkReadDebounceProvider.overrideWithValue(markReadDebounce),
      if (authState != null) authProvider.overrideWith(() => _FakeAuth(authState)),
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

  test('duplicate message.created (own send echo) does not POST a read',
      () async {
    final c = makeContainer(
      authState: const AuthAuthenticated(
        user: AuthUser(id: 2, name: 'Eddie', email: 'e@x.com'),
        bands: [],
      ),
    );
    // Hold a listener: the delayed awaits below yield to the event loop, and
    // chatThreadProvider is autoDispose — without a listener it would tear
    // down (and its state reset) as soon as load()'s keepAlive is released.
    final sub = c.listen(chatThreadProvider(5), (_, __) {});
    addTearDown(sub.close);
    // load() itself calls markRead() once for the initial page.
    await c.read(chatThreadProvider(5).notifier).load();
    expect(readPostCount, 1);

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
    await Future<void>.delayed(Duration.zero);
    // Duplicate id → not appended at all, so no debounce timer is armed and
    // no extra read POST fires.
    expect(readPostCount, 1);
  });

  test('an appended message authored by the current user does not POST a '
      'read (only messages from others should)', () async {
    final c = makeContainer(
      authState: const AuthAuthenticated(
        user: AuthUser(id: 2, name: 'Eddie', email: 'e@x.com'),
        bands: [],
      ),
    );
    final sub = c.listen(chatThreadProvider(5), (_, __) {});
    addTearDown(sub.close);
    await c.read(chatThreadProvider(5).notifier).load();
    expect(readPostCount, 1);

    capturedHandler!('message.created', {
      'message': {
        'id': 99,
        'conversation_id': 5,
        'user_id': 2,
        'user_name': 'Eddie',
        'body': 'from another device',
        'created_at': '2026-07-12T14:02:00Z',
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(c.read(chatThreadProvider(5)).messages.length, 2);
    expect(readPostCount, 1, reason: 'own-authored append must not mark read');
  });

  test('a burst of messages from someone else debounces to a single read '
      'POST', () async {
    fakeAsync((async) {
      final c = makeContainer(
        authState: const AuthAuthenticated(
          user: AuthUser(id: 2, name: 'Eddie', email: 'e@x.com'),
          bands: [],
        ),
        markReadDebounce: const Duration(milliseconds: 1500),
      );
      final sub = c.listen(chatThreadProvider(5), (_, __) {});
      addTearDown(sub.close);
      c.read(chatThreadProvider(5).notifier).load();
      async.elapse(Duration.zero);
      expect(readPostCount, 1, reason: 'initial load marks read once');

      for (var i = 0; i < 3; i++) {
        capturedHandler!('message.created', {
          'message': {
            'id': 100 + i,
            'conversation_id': 5,
            'user_id': 3,
            'user_name': 'Sam',
            'body': 'msg $i',
            'created_at': '2026-07-12T14:0${3 + i}:00Z',
          },
        });
        async.elapse(const Duration(milliseconds: 200));
      }
      expect(readPostCount, 1, reason: 'debounce window has not elapsed yet');

      async.elapse(const Duration(seconds: 2));
      expect(readPostCount, 2,
          reason: 'the burst collapses into a single trailing read POST');
    });
  });

  test('markRead invalidates both chatConversationsProvider and '
      'topicThreadProvider so a CommentBar badge on a detail screen '
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
    // listener, mirroring how a CommentBar on a detail screen watches it.
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

  test('realtime conversation.delivered patches the participant', () async {
    final c = makeContainer();
    await c.read(chatThreadProvider(5).notifier).load();
    capturedHandler!('conversation.delivered', {
      'user_id': 3,
      'last_delivered_at': '2020-07-12T15:00:00Z',
    });
    final p = c
        .read(chatThreadProvider(5))
        .participants
        .firstWhere((p) => p.userId == 3);
    expect(p.deliveredAt, DateTime.parse('2020-07-12T15:00:00Z'));
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

  group('toggleReactionList', () {
    test('adds when absent, removes when present, drops empty groups', () {
      const emoji = '👍';
      var reactions = toggleReactionList(const [], emoji, 2);
      expect(reactions.single.count, 1);
      expect(reactions.single.userIds, [2]);

      reactions = toggleReactionList(reactions, emoji, 3);
      expect(reactions.single.count, 2);

      reactions = toggleReactionList(reactions, emoji, 2);
      expect(reactions.single.count, 1);
      expect(reactions.single.userIds, [3]);

      reactions = toggleReactionList(reactions, emoji, 3);
      expect(reactions, isEmpty);
    });
  });

  const currentUserId = 2;

  test('toggleReaction is optimistic and reconciles with server aggregate',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        if (options.method == 'POST' && options.path.endsWith('/reactions')) {
          return json(200, {
            'reactions': [
              {
                'emoji': '👍',
                'count': 1,
                'user_ids': [currentUserId],
              },
            ],
          });
        }
        return json(200, threadJson);
      });
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatTypingTtlProvider.overrideWithValue(Duration.zero),
      authProvider.overrideWith(() => _FakeAuth(const AuthAuthenticated(
            user: AuthUser(id: currentUserId, name: 'Eddie', email: 'e@x.com'),
            bands: [],
          ))),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) {
        capturedHandler = onEvent;
        return null; // test seam: no live subscription, nothing to unbind
      }),
    ]);
    addTearDown(container.dispose);

    // Hold a listener: chatThreadProvider is autoDispose, and without one
    // the notifier tears down between load() and toggleReaction() the
    // moment load()'s internal keepAlive is released.
    final sub = container.listen(chatThreadProvider(5), (_, __) {});
    addTearDown(sub.close);

    final notifier = container.read(chatThreadProvider(5).notifier);
    await notifier.load();

    await notifier.toggleReaction(1, '👍', currentUserId);
    // Immediately after the await both the optimistic and reconciled state
    // agree; assert the message now carries the server aggregate:
    final message =
        container.read(chatThreadProvider(5)).messages.single;
    expect(message.reactions.single.emoji, '👍');
    expect(message.reactions.single.reactedBy(currentUserId), isTrue);
  });

  test('toggleReaction rolls back on API failure', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        if (options.method == 'POST' && options.path.endsWith('/reactions')) {
          return json(500, {'message': 'nope'});
        }
        return json(200, threadJson);
      });
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatTypingTtlProvider.overrideWithValue(Duration.zero),
      authProvider.overrideWith(() => _FakeAuth(const AuthAuthenticated(
            user: AuthUser(id: currentUserId, name: 'Eddie', email: 'e@x.com'),
            bands: [],
          ))),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) {
        capturedHandler = onEvent;
        return null; // test seam: no live subscription, nothing to unbind
      }),
    ]);
    addTearDown(container.dispose);

    // Hold a listener: chatThreadProvider is autoDispose, and without one
    // the notifier tears down between load() and toggleReaction() the
    // moment load()'s internal keepAlive is released.
    final sub = container.listen(chatThreadProvider(5), (_, __) {});
    addTearDown(sub.close);

    final notifier = container.read(chatThreadProvider(5).notifier);
    await notifier.load();

    await notifier.toggleReaction(1, '👍', currentUserId);
    final message =
        container.read(chatThreadProvider(5)).messages.single;
    expect(message.reactions, isEmpty);
    expect(container.read(chatThreadProvider(5)).error, isNotNull);
  });

  test('toggleReaction ignores a second call while the first is in flight',
      () async {
    var reactionRequests = 0;
    final reactionCompleter = Completer<ResponseBody>();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) {
        if (options.method == 'POST' && options.path.endsWith('/reactions')) {
          reactionRequests++;
          return reactionCompleter.future;
        }
        return Future.value(json(200, threadJson));
      });
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatTypingTtlProvider.overrideWithValue(Duration.zero),
      authProvider.overrideWith(() => _FakeAuth(const AuthAuthenticated(
            user: AuthUser(id: currentUserId, name: 'Eddie', email: 'e@x.com'),
            bands: [],
          ))),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) {
        capturedHandler = onEvent;
        return null; // test seam: no live subscription, nothing to unbind
      }),
    ]);
    addTearDown(container.dispose);

    // Hold a listener: chatThreadProvider is autoDispose, and without one
    // the notifier tears down between load() and toggleReaction() the
    // moment load()'s internal keepAlive is released.
    final sub = container.listen(chatThreadProvider(5), (_, __) {});
    addTearDown(sub.close);

    final notifier = container.read(chatThreadProvider(5).notifier);
    await notifier.load();

    // Fire two toggles back-to-back before the first request resolves
    // (sheet emoji tap immediately followed by tapping the optimistic
    // chip). Only the first should reach the network.
    final firstToggle = notifier.toggleReaction(1, '👍', currentUserId);
    final secondToggle = notifier.toggleReaction(1, '👍', currentUserId);

    reactionCompleter.complete(json(200, {
      'reactions': [
        {
          'emoji': '👍',
          'count': 1,
          'user_ids': [currentUserId],
        },
      ],
    }));
    await firstToggle;
    await secondToggle;

    expect(reactionRequests, 1,
        reason: 'a fast double-toggle must not issue two concurrent requests');
    final message = container.read(chatThreadProvider(5)).messages.single;
    expect(message.reactions.single.emoji, '👍');
    expect(message.reactions.single.reactedBy(currentUserId), isTrue);
  });

  test('toggleReaction ignores the unauthenticated sentinel user id (-1) '
      'and issues no request', () async {
    var reactionRequests = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        if (options.method == 'POST' && options.path.endsWith('/reactions')) {
          reactionRequests++;
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

    // Hold a listener: chatThreadProvider is autoDispose, and without one
    // the notifier tears down between load() and toggleReaction() the
    // moment load()'s internal keepAlive is released.
    final sub = container.listen(chatThreadProvider(5), (_, __) {});
    addTearDown(sub.close);

    final notifier = container.read(chatThreadProvider(5).notifier);
    await notifier.load();

    await notifier.toggleReaction(1, '👍', -1);

    expect(reactionRequests, 0,
        reason: 'the -1 unauthenticated sentinel must never reach the API');
    final message = container.read(chatThreadProvider(5)).messages.single;
    expect(message.reactions, isEmpty);
  });

  group('dmMessageStatus', () {
    final msg = ChatMessage.fromJson({
      'id': 1,
      'conversation_id': 5,
      'user_id': 2,
      'body': 'hi',
      'created_at': '2020-07-12T14:00:00Z',
    });
    ChatParticipant other({String? read, String? delivered}) =>
        ChatParticipant.fromJson({
          'user_id': 3,
          'name': 'Sam',
          'last_read_at': read,
          'last_delivered_at': delivered,
        });

    test('none when the other participant has neither receipt', () {
      expect(dmMessageStatus(msg, [other()], 2), DmMessageStatus.none);
    });

    test('delivered when delivered at/after created but not read', () {
      expect(
        dmMessageStatus(msg, [other(delivered: '2020-07-12T14:00:00Z')], 2),
        DmMessageStatus.delivered,
      );
    });

    test('seen wins over delivered', () {
      expect(
        dmMessageStatus(
            msg,
            [
              other(
                  read: '2020-07-12T14:30:00Z',
                  delivered: '2020-07-12T14:00:00Z')
            ],
            2),
        DmMessageStatus.seen,
      );
    });

    test('receipts older than the message do not count', () {
      expect(
        dmMessageStatus(
            msg,
            [
              other(
                  read: '2020-07-12T13:00:00Z',
                  delivered: '2020-07-12T13:30:00Z')
            ],
            2),
        DmMessageStatus.none,
      );
    });
  });

  test('seenByNames lists other readers only', () {
    final msg = ChatMessage.fromJson({
      'id': 1,
      'conversation_id': 5,
      'user_id': 2,
      'body': 'hi',
      'created_at': '2020-07-12T14:00:00Z',
    });
    final participants = [
      ChatParticipant.fromJson(
          {'user_id': 2, 'name': 'Me', 'last_read_at': '2020-07-12T15:00:00Z'}),
      ChatParticipant.fromJson({
        'user_id': 3,
        'name': 'Sam',
        'last_read_at': '2020-07-12T15:00:00Z'
      }),
      ChatParticipant.fromJson({
        'user_id': 4,
        'name': 'Kim',
        'last_read_at': '2020-07-12T13:00:00Z'
      }),
    ];
    expect(seenByNames(msg, participants, 2), ['Sam']);
  });

  test('realtime message.updated with reactions patches the message',
      () async {
    final c = makeContainer();
    await c.read(chatThreadProvider(5).notifier).load();

    capturedHandler!('message.updated', {
      'message': {
        'id': 1,
        'conversation_id': 5,
        'user_id': 3,
        'user_name': 'Sam',
        'body': 'you around?',
        'created_at': '2026-07-12T14:00:00Z',
        'reactions': [
          {'emoji': '🎉', 'count': 1, 'user_ids': [3]},
        ],
      },
    });
    final message =
        c.read(chatThreadProvider(5)).messages.single;
    expect(message.reactions.single.emoji, '🎉');
  });
}
