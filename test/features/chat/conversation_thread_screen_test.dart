import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/providers/active_chat_conversation_provider.dart';
import 'package:tts_bandmate/features/chat/providers/chat_thread_provider.dart';
import 'package:tts_bandmate/features/chat/screens/attachment_viewer_screen.dart';
import 'package:tts_bandmate/features/chat/screens/conversation_thread_screen.dart';
import 'package:tts_bandmate/shared/widgets/auth_thumbnail.dart';
import 'package:dio/dio.dart';

import '../../helpers/test_harness.dart';

/// Fixed-state auth notifier — matches the idiom used by
/// chat_thread_provider_test.dart so widget tests can pin `currentUserId`.
class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._state);
  final AuthState _state;

  @override
  Future<AuthState> build() async => _state;
}

const _currentUserId = 2;

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

  testWidgets('inserts date separators between messages on different days',
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
                'body': 'from june',
                'created_at': '2020-06-03T14:00:00Z',
              },
              {
                'id': 2,
                'conversation_id': 5,
                'user_id': 3,
                'user_name': 'Sam',
                'body': 'from july',
                'created_at': '2020-07-02T14:00:00Z',
              },
            ],
            'participants': [
              {'user_id': 3, 'name': 'Sam', 'last_read_at': null},
            ],
            'channel': 'private-conversation.5',
            'has_more': false,
          }));

    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatMarkReadDebounceProvider.overrideWithValue(Duration.zero),
      chatChannelBinderProvider.overrideWithValue((_, __) => null),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: ConversationThreadScreen(conversationId: 5, title: 'Sam'),
      ),
    ));
    await tester.pumpAndSettle();

    // These dates are far in the past (2020), so no matter what a real
    // test-run clock reads, both separators fall back to the full
    // date-with-year form rather than a "Today"/weekday label — making the
    // assertion truly clock-independent. The June→July day change still
    // yields exactly two separators: one above the first message, one at
    // the day change.
    expect(find.textContaining('2020'), findsNWidgets(2));
  });

  testWidgets('tapping a bubble reveals its timestamp (with edited marker)',
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
                'body': 'fixed a typo here',
                'created_at': '2026-07-12T14:00:00Z',
                'edited_at': '2026-07-12T14:05:00Z',
              },
            ],
            'participants': [
              {'user_id': 3, 'name': 'Sam', 'last_read_at': null},
            ],
            'channel': 'private-conversation.5',
            'has_more': false,
          }));

    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatMarkReadDebounceProvider.overrideWithValue(Duration.zero),
      chatChannelBinderProvider.overrideWithValue((_, __) => null),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: ConversationThreadScreen(conversationId: 5, title: 'Sam'),
      ),
    ));
    await tester.pumpAndSettle();

    // Hidden until tapped (the old always-on 'edited' label is gone).
    expect(find.textContaining('edited'), findsNothing);

    await tester.tap(find.text('fixed a typo here'));
    await tester.pump();
    expect(find.textContaining('· edited'), findsOneWidget);

    // Tapping again hides it.
    await tester.tap(find.text('fixed a typo here'));
    await tester.pump();
    expect(find.textContaining('edited'), findsNothing);
  });

  testWidgets('tapping an attachment opens the fullscreen viewer',
      (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        if (options.path.contains('/attachments/')) {
          // Viewer fetch: any bytes will do — the screen itself is what the
          // test asserts on, not a decoded image.
          return ResponseBody.fromBytes(Uint8List.fromList([0]), 200);
        }
        return json(200, {
          'conversation': {'id': 5, 'type': 'dm', 'title': 'Sam'},
          'messages': [
            {
              'id': 1,
              'conversation_id': 5,
              'user_id': 3,
              'user_name': 'Sam',
              'body': '',
              'created_at': '2026-07-12T14:00:00Z',
              'attachments': [
                {'id': 7, 'width': 100, 'height': 80},
              ],
            },
          ],
          'participants': [
            {'user_id': 3, 'name': 'Sam', 'last_read_at': null},
          ],
          'channel': 'private-conversation.5',
          'has_more': false,
        });
      });

    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatMarkReadDebounceProvider.overrideWithValue(Duration.zero),
      chatChannelBinderProvider.overrideWithValue((_, __) => null),
      secureStorageProvider.overrideWithValue(FakeSecureStorage()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: ConversationThreadScreen(conversationId: 5, title: 'Sam'),
      ),
    ));
    await tester.pump();
    // A real Timer/microtask hop is needed for the stubbed Dio fetch to
    // resolve — a bare pump() (no duration) does not advance pending Timers,
    // only the microtask queue + one frame, so the initial load() never
    // completes. pump(Duration.zero) advances the fake clock enough for the
    // stub's Future chain to settle. pumpAndSettle isn't usable anywhere in
    // this test: once the viewer is pushed below, its Image.memory decode
    // failure (see note below) keeps scheduling frames forever.
    await tester.pump(Duration.zero);

    await tester.tap(find.byType(AuthThumbnail));
    await tester.pump();
    await tester.pump(Duration.zero);

    expect(find.byType(AttachmentViewerScreen), findsOneWidget);
  });

  /// A single-message thread (message id 1, authored by user 3 "Sam" — not
  /// the current user, and the caller has no moderator rights) with
  /// [reactions] seeded onto that message. [captured] accumulates every
  /// request the StubAdapter sees so tests can assert on method + path;
  /// [reactionResponse] is what a reactions POST/DELETE returns.
  Future<ProviderContainer> pumpReactionsThread(
    WidgetTester tester, {
    List<Map<String, dynamic>> reactions = const [],
    required List<RequestOptions> captured,
    required Map<String, dynamic> reactionResponse,
  }) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        captured.add(options);
        if (options.path.endsWith('/reactions') ||
            options.path.contains('/reactions/')) {
          return json(200, reactionResponse);
        }
        return json(200, {
          'conversation': {
            'id': 5,
            'type': 'dm',
            'title': 'Sam',
            'can_moderate': false,
          },
          'messages': [
            {
              'id': 1,
              'conversation_id': 5,
              'user_id': 3,
              'user_name': 'Sam',
              'body': 'you around?',
              'created_at': '2026-07-12T14:00:00Z',
              'reactions': reactions,
            },
          ],
          'participants': [
            {'user_id': 3, 'name': 'Sam', 'last_read_at': null},
          ],
          'channel': 'private-conversation.5',
          'has_more': false,
        });
      });

    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
      chatMarkReadDebounceProvider.overrideWithValue(Duration.zero),
      authProvider.overrideWith(() => _FakeAuth(const AuthAuthenticated(
            user: AuthUser(id: _currentUserId, name: 'Eddie', email: 'e@x.com'),
            bands: [],
          ))),
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
    return container;
  }

  testWidgets('long-press on another user\'s message opens the emoji row',
      (tester) async {
    // Thread with one message from user 3 (not the current user), no
    // moderator rights. Long-press the bubble:
    final captured = <RequestOptions>[];
    await pumpReactionsThread(tester,
        captured: captured, reactionResponse: {'reactions': <dynamic>[]});

    await tester.longPress(find.text('you around?'));
    await tester.pumpAndSettle();

    // The sheet now opens (pre-change it early-returned) with the quick set
    // visible and no Edit/Delete for someone else's message:
    expect(find.text('👍'), findsOneWidget);
    expect(find.text('🎉'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('tapping a quick emoji posts the reaction and renders a chip',
      (tester) async {
    final captured = <RequestOptions>[];
    await pumpReactionsThread(tester, captured: captured, reactionResponse: {
      'reactions': [
        {
          'emoji': '👍',
          'count': 1,
          'user_ids': [_currentUserId],
        },
      ],
    });

    await tester.longPress(find.text('you around?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();

    // Optimistic chip under the bubble (emoji + count):
    expect(find.text('👍 1'), findsOneWidget);
    // And the POST went out:
    expect(
      captured.any((r) =>
          r.method == 'POST' && r.path == '/api/mobile/messages/1/reactions'),
      isTrue,
    );
  });

  testWidgets('tapping an existing chip toggles it off', (tester) async {
    // Seed the thread page JSON so message 1 already has
    // {'emoji':'👍','count':1,'user_ids':[<currentUserId>]} and stub the
    // DELETE to return {'reactions': []}. Then:
    final captured = <RequestOptions>[];
    await pumpReactionsThread(
      tester,
      reactions: [
        {
          'emoji': '👍',
          'count': 1,
          'user_ids': [_currentUserId],
        },
      ],
      captured: captured,
      reactionResponse: {'reactions': <dynamic>[]},
    );

    expect(find.text('👍 1'), findsOneWidget);

    await tester.tap(find.text('👍 1'));
    await tester.pumpAndSettle();

    expect(find.text('👍 1'), findsNothing);
    expect(captured.any((r) => r.method == 'DELETE'), isTrue);
  });
}
