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

  testWidgets('topic rows render item-type icons', (tester) async {
    final container = ProviderContainer(overrides: [
      chatConversationsProvider.overrideWith((ref) async => [
            const Conversation(
                id: 3,
                type: 'topic',
                title: 'Summer Gala',
                topicType: 'booking'),
            const Conversation(
                id: 4,
                type: 'topic',
                title: 'Festival Set',
                topicType: 'event'),
            const Conversation(
                id: 5,
                type: 'topic',
                title: 'Tuesday practice',
                topicType: 'rehearsal'),
            const Conversation(id: 6, type: 'topic', title: 'Thread'),
          ]),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(home: MessagesScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(CupertinoIcons.briefcase), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.calendar), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.music_note_2), findsOneWidget);
    // Unknown/missing topic_type falls back to a generic thread icon.
    expect(find.byIcon(CupertinoIcons.chat_bubble_2), findsOneWidget);
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
