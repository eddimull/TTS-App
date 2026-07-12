import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/providers/active_chat_conversation_provider.dart';
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
      chatMarkReadDebounceProvider.overrideWithValue(Duration.zero),
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

  /// Builds a page of [count] messages (ids 100, 101, ... newest last, oldest
  /// first — the wire order state.messages expects) with enough body text
  /// height per bubble that the list actually scrolls in the fixed-size test
  /// surface.
  List<Map<String, dynamic>> messagesPage({
    required int startId,
    required int count,
  }) =>
      [
        for (var i = 0; i < count; i++)
          {
            'id': startId + i,
            'conversation_id': 5,
            'user_id': 3,
            'user_name': 'Sam',
            'body': 'message number ${startId + i}',
            'created_at': '2026-07-12T14:${(i % 60).toString().padLeft(2, '0')}:00Z',
          },
      ];

  testWidgets(
      'initial open does not fire loadMore even though the list settles at '
      'scroll offset 0 (the reversed list\'s natural resting position)',
      (tester) async {
    var messagesGetCount = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        if (options.path.endsWith('/messages')) {
          messagesGetCount++;
        }
        return json(200, {
          'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
          'messages': messagesPage(startId: 100, count: 30),
          'participants': <dynamic>[],
          'channel': 'private-conversation.5',
          // has_more: true means a wrongly-armed top trigger would fire a
          // second GET as soon as the first frame settles.
          'has_more': true,
        });
      });

    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) => null),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: ConversationThreadScreen(conversationId: 5, title: 'Sam'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(messagesGetCount, 1,
        reason: 'the initial settle must not itself trigger loadMore()');
  });

  testWidgets(
      'loadMore (prepend) does not scroll the viewport back to the newest '
      'message', (tester) async {
    var messagesGetCount = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        if (options.method != 'GET' || !options.path.endsWith('/messages')) {
          // markRead POSTs and any other non-page-fetch call — not counted.
          return json(200, {});
        }
        messagesGetCount++;
        if (messagesGetCount == 1) {
          return json(200, {
            'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
            'messages': messagesPage(startId: 200, count: 30),
            'participants': <dynamic>[],
            'channel': 'private-conversation.5',
            'has_more': true,
          });
        }
        // The loadMore (before=200) page: older history.
        return json(200, {
          'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
          'messages': messagesPage(startId: 150, count: 20),
          'participants': <dynamic>[],
          'channel': 'private-conversation.5',
          'has_more': false,
        });
      });

    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatMarkReadDebounceProvider.overrideWithValue(Duration.zero),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) => null),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: ConversationThreadScreen(conversationId: 5, title: 'Sam'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(messagesGetCount, 1);

    // The newest message (highest id) must be showing — the reversed list's
    // natural resting position is scroll offset 0, pinned to the bottom.
    expect(find.text('message number 229'), findsOneWidget);

    // Scroll toward older history: in a reversed list that means dragging
    // content downward (revealing higher scroll offsets, toward
    // maxScrollExtent) which the test harness expresses as a drag with a
    // positive dy.
    await tester.drag(
      find.byType(ListView),
      const Offset(0, 5000),
    );
    await tester.pumpAndSettle();

    expect(messagesGetCount, 2,
        reason: 'scrolling toward history must trigger loadMore()');

    // The message that was on screen before loadMore (id 229, the newest)
    // must still be reachable without the viewport having been reset back to
    // it — i.e. the prepend must not have called animateTo/jumpTo. We
    // confirm by checking that an *older* message from the newly-prepended
    // page is now present without further scrolling — proving the prepend
    // didn't yank us back down past it.
    expect(find.text('message number 150'), findsOneWidget);
  });

  testWidgets(
      'an incoming realtime append from someone else is visible without any '
      'manual scroll (the reversed list stays pinned to the bottom)',
      (tester) async {
    void Function(String, Map<String, dynamic>)? handler;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async => json(200, {
            'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
            'messages': messagesPage(startId: 300, count: 10),
            'participants': <dynamic>[],
            'channel': 'private-conversation.5',
            'has_more': false,
          }));

    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatMarkReadDebounceProvider.overrideWithValue(Duration.zero),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) {
        handler = onEvent;
        return null;
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

    handler!('message.created', {
      'message': {
        'id': 999,
        'conversation_id': 5,
        'user_id': 3,
        'user_name': 'Sam',
        'body': 'brand new message',
        'created_at': '2026-07-12T14:59:00Z',
      },
    });
    await tester.pump();
    // Drain the (zero-duration in this test) debounced markRead timer before
    // teardown — an unfired Timer trips flutter_test's pending-timer
    // invariant even though the assertions below have already run.
    await tester.pump(Duration.zero);

    expect(find.text('brand new message'), findsOneWidget,
        reason: 'a near-bottom reader must see a new append immediately, '
            'with no explicit scroll-to-bottom needed');
  });

  testWidgets(
      'opening the thread marks it active, and closing it clears the marker',
      (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async => json(200, {
            'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
            'messages': <dynamic>[],
            'participants': <dynamic>[],
            'channel': 'private-conversation.5',
            'has_more': false,
          }));

    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) => null),
    ]);
    addTearDown(container.dispose);

    expect(container.read(activeChatConversationProvider), isNull);

    // A ValueKey keyed on conversationId forces the framework to treat a
    // change of conversation as a brand new widget (new State, fresh
    // initState/dispose) rather than reusing the existing State object —
    // matching how go_router pushes a distinct route per conversation id.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: ConversationThreadScreen(
          key: ValueKey('thread-5'),
          conversationId: 5,
          title: 'Sam',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(container.read(activeChatConversationProvider), 5,
        reason: 'opening the thread must mark it as the active conversation');

    // Swap in an unrelated widget so the thread screen's State is disposed
    // (its dispose() reads/clears the provider before super.dispose()).
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(home: CupertinoPageScaffold(child: SizedBox())),
    ));
    await tester.pumpAndSettle();

    expect(container.read(activeChatConversationProvider), isNull,
        reason: 'closing the thread must clear the active-conversation '
            'marker so a background push for it is no longer suppressed');
  });

  testWidgets('a failed send restores the typed text so it is not lost',
      (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        if (options.method == 'POST' && options.path.endsWith('/messages')) {
          throw DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 500),
            type: DioExceptionType.badResponse,
          );
        }
        return json(200, {
          'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
          'messages': <dynamic>[],
          'participants': <dynamic>[],
          'channel': 'private-conversation.5',
          'has_more': false,
        });
      });

    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatChannelBinderProvider.overrideWithValue((channel, onEvent) => null),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: ConversationThreadScreen(conversationId: 5, title: 'Sam'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField), 'this will fail');
    await tester.tap(find.byIcon(CupertinoIcons.arrow_up_circle_fill));
    await tester.pumpAndSettle();

    expect(find.text('this will fail'), findsOneWidget,
        reason: 'a failed send must restore the typed text, not lose it');
  });
}
