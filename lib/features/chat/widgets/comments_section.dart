import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../providers/topic_thread_provider.dart';

export '../providers/topic_thread_provider.dart' show TopicRef, topicThreadProvider;

/// Embeddable "Comments" section for detail screens: header, the 3 most
/// recent comments, and an unread-aware "View all" row that opens the full
/// thread screen.
///
/// For bookings topics, [bandId] must be provided. For events and rehearsals,
/// it is ignored.
class CommentsSection extends ConsumerWidget {
  const CommentsSection({
    super.key,
    required this.kind,
    required this.idOrKey,
    this.bandId,
  });

  final String kind;
  final String idOrKey;
  final int? bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topic = TopicRef(kind: kind, idOrKey: idOrKey, bandId: bandId);
    final pageAsync = ref.watch(topicThreadProvider(topic));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Comments',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        pageAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CupertinoActivityIndicator()),
          ),
          // Comments are secondary content on a detail screen — a load
          // failure shows a quiet retry row, not a full-screen error.
          error: (_, __) => CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => ref.invalidate(topicThreadProvider(topic)),
            child: Text(
              'Couldn\'t load comments — tap to retry',
              style: TextStyle(fontSize: 13, color: context.secondaryText),
            ),
          ),
          data: (page) {
            final recent = page.messages.length <= 3
                ? page.messages
                : page.messages.sublist(page.messages.length - 3);
            final unread = page.conversation.unreadCount;
            final total = page.messages.length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (recent.isEmpty)
                  Text(
                    'No comments yet.',
                    style: TextStyle(fontSize: 13, color: context.secondaryText),
                  ),
                for (final message in recent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: RichText(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: TextStyle(fontSize: 14, color: context.primaryText),
                        children: [
                          TextSpan(
                            text: '${message.userName}: ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: message.isDeleted
                                ? 'Message deleted'
                                : (message.body.isEmpty && message.attachments.isNotEmpty
                                    ? '📷 Photo'
                                    : message.body),
                          ),
                        ],
                      ),
                    ),
                  ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => context.push(
                    '/conversations/${page.conversation.id}',
                    extra: {'title': page.conversation.title},
                  ),
                  child: Text(
                    unread > 0
                        ? 'View all ($total) · $unread unread'
                        : (total == 0 ? 'Add a comment' : 'View all ($total)'),
                    style: TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
