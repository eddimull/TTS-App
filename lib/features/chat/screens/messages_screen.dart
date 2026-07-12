import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/models/conversation.dart';
import '../providers/conversations_provider.dart';

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(chatConversationsProvider);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Messages'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => context.push('/messages/new'),
          child: const Icon(CupertinoIcons.square_pencil),
        ),
      ),
      child: SafeArea(
        child: listAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => ErrorView(
            message: ErrorView.friendlyMessage(e),
            onRetry: () => ref.invalidate(chatConversationsProvider),
          ),
          data: (conversations) {
            if (conversations.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.chat_bubble_2,
                        size: 44, color: context.tertiaryText),
                    const SizedBox(height: 8),
                    Text('No messages yet',
                        style: TextStyle(color: context.secondaryText)),
                  ],
                ),
              );
            }
            return ListView.builder(
              itemCount: conversations.length,
              itemBuilder: (_, i) => _ConversationRow(
                conversation: conversations[i],
                onTap: () => context.push(
                  '/conversations/${conversations[i].id}',
                  extra: {'title': conversations[i].title},
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.conversation, required this.onTap});
  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.unreadCount > 0;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              conversation.type == 'dm'
                  ? CupertinoIcons.person_crop_circle
                  : CupertinoIcons.person_3_fill,
              size: 34,
              color: context.secondaryText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                      color: context.primaryText,
                    ),
                  ),
                  if (conversation.lastMessagePreview != null)
                    Text(
                      conversation.lastMessagePreview!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: context.secondaryText),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (conversation.lastMessageAt != null)
                  Text(
                    timeago.format(conversation.lastMessageAt!),
                    style: TextStyle(fontSize: 12, color: context.tertiaryText),
                  ),
                if (hasUnread)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${conversation.unreadCount}',
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
