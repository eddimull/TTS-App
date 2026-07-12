import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/models/conversation.dart';
import 'package:tts_bandmate/features/chat/providers/conversations_provider.dart';
import 'package:tts_bandmate/features/chat/screens/messages_screen.dart';

void main() {
  testWidgets('shows conversations with unread badge', (tester) async {
    final container = ProviderContainer(overrides: [
      chatConversationsProvider.overrideWith((ref) async => [
            const Conversation(
                id: 1,
                type: 'dm',
                title: 'Sam',
                lastMessagePreview: 'see you at 8',
                unreadCount: 2),
            const Conversation(id: 2, type: 'band', title: 'The Band'),
          ]),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(home: MessagesScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('see you at 8'), findsOneWidget);
    expect(find.text('The Band'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // unread badge
  });

  testWidgets('shows empty state when no conversations', (tester) async {
    final container = ProviderContainer(overrides: [
      chatConversationsProvider.overrideWith((ref) async => []),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(home: MessagesScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No messages yet'), findsOneWidget);
  });
}
