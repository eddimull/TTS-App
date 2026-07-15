import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/widgets/comment_bar.dart';

import '../../helpers/test_harness.dart';

void main() {
  Map<String, dynamic> threadBody({
    List<Map<String, dynamic>> messages = const [],
    int unread = 0,
  }) =>
      {
        'conversation': {
          'id': 5,
          'type': 'topic',
          'title': 'Gig at Blue Room',
          'unread_count': unread,
        },
        'messages': messages,
        'participants': [],
        'channel': 'private-conversation.5',
        'has_more': false,
      };

  Map<String, dynamic> message(int id, String name, String body) => {
        'id': id,
        'conversation_id': 5,
        'user_id': id,
        'user_name': name,
        'body': body,
        'created_at': '2026-07-12T14:0$id:00Z',
      };

  ProviderContainer containerWith(
      Future<ResponseBody> Function(RequestOptions) handler) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter(handler);
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Widget host(ProviderContainer container) => UncontrolledProviderScope(
        container: container,
        child: const CupertinoApp(
          home: CupertinoPageScaffold(
            child: CommentBarBody(
              topic: TopicRef(kind: 'events', idOrKey: 'abc123'),
              child: SizedBox.expand(),
            ),
          ),
        ),
      );

  /// All RichText content flattened — Icon renders through RichText too, so
  /// individual find.byType(RichText) matches are ambiguous.
  String allRichText(WidgetTester tester) => tester
      .widgetList<RichText>(find.byType(RichText))
      .map((r) => r.text.toPlainText())
      .join('\n');

  testWidgets('shows the latest comment and the unread badge', (tester) async {
    final container = containerWith((_) async => json(
        200,
        threadBody(messages: [
          message(1, 'Eddie', 'sound check at 6'),
          message(2, 'Pat', 'see you at 6'),
        ], unread: 2)));

    await tester.pumpWidget(host(container));
    await tester.pumpAndSettle();

    expect(allRichText(tester), contains('Pat: see you at 6'));
    expect(allRichText(tester), isNot(contains('Eddie: sound check')));
    expect(find.text('2'), findsOneWidget); // unread badge
  });

  testWidgets('empty thread shows Add a comment…', (tester) async {
    final container = containerWith((_) async => json(200, threadBody()));

    await tester.pumpWidget(host(container));
    await tester.pumpAndSettle();

    expect(find.text('Add a comment…'), findsOneWidget);
  });

  testWidgets('load failure shows quiet retry row; tap retries', (tester) async {
    var calls = 0;
    final container = containerWith((_) async {
      calls++;
      if (calls == 1) return json(500, {'message': 'boom'});
      return json(200, threadBody(messages: [message(1, 'Eddie', 'hi')]));
    });

    await tester.pumpWidget(host(container));
    await tester.pumpAndSettle();
    expect(find.text('Comments unavailable — tap to retry'), findsOneWidget);

    await tester.tap(find.text('Comments unavailable — tap to retry'));
    await tester.pumpAndSettle();
    expect(allRichText(tester), contains('Eddie: hi'));
  });

  testWidgets('renders a shell while loading (no layout jump)', (tester) async {
    final container = containerWith((_) async => json(200, threadBody()));

    await tester.pumpWidget(host(container));
    // First frame only — the stubbed response hasn't resolved yet.
    expect(find.text('Comments'), findsOneWidget);
  });
}
