import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/chat_message.dart';
import '../providers/topic_thread_provider.dart';

export '../providers/topic_thread_provider.dart' show TopicRef, topicThreadProvider;

/// Detail-screen body wrapper: hosts the scrollable content and docks a
/// [CommentBar] beneath it so the comments entry point stays visible
/// regardless of scroll position.
class CommentBarBody extends StatelessWidget {
  const CommentBarBody({super.key, required this.topic, required this.child});

  final TopicRef topic;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(child: child),
          CommentBar(topic: topic),
        ],
      );
}

/// Pinned comment bar: 💬 icon, one-line latest comment, unread badge, and a
/// chevron. Tapping opens the full thread screen. Always rendered — an empty
/// thread shows "Add a comment…" so the feature stays discoverable.
class CommentBar extends ConsumerWidget {
  const CommentBar({super.key, required this.topic});

  final TopicRef topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(topicThreadProvider(topic));

    // Riverpod's FutureProvider re-enters AsyncLoading (with hasError still
    // true) while retrying after a failure, so when() would route back to
    // loading() instead of error() during a retry. Check hasError first so
    // the quiet retry row stays visible until the retry actually resolves.
    final content = pageAsync.hasError
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.invalidate(topicThreadProvider(topic)),
            child: _BarRow(
              child: Text('Comments unavailable — tap to retry',
                  style: TextStyle(fontSize: 14, color: context.secondaryText)),
            ),
          )
        : pageAsync.when(
            loading: () => _BarRow(
              child: Text('Comments',
                  style: TextStyle(fontSize: 14, color: context.secondaryText)),
            ),
            // Unreachable: the hasError pre-check above intercepts every error
            // state (including loading-with-previous-error). when() still
            // requires the handler.
            error: (_, __) => const SizedBox.shrink(),
            data: (page) {
              final latest = page.messages.isEmpty ? null : page.messages.last;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.push(
                  '/conversations/${page.conversation.id}',
                  extra: {'title': page.conversation.title},
                ),
                child: _BarRow(
                  unread: page.conversation.unreadCount,
                  showChevron: true,
                  child: latest == null
                      ? Text('Add a comment…',
                          style: TextStyle(
                              fontSize: 14, color: context.secondaryText))
                      : RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: TextStyle(
                                fontSize: 14, color: context.primaryText),
                            children: [
                              TextSpan(
                                text: '${latest.userName}: ',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              TextSpan(text: _previewText(latest)),
                            ],
                          ),
                        ),
                ),
              );
            },
          );

    return Container(
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).barBackgroundColor,
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(top: false, child: content),
    );
  }

  static String _previewText(ChatMessage m) {
    if (m.isDeleted) return 'Message deleted';
    if (m.body.isEmpty && m.attachments.isNotEmpty) return '📷 Photo';
    return m.body;
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow(
      {required this.child, this.unread = 0, this.showChevron = false});

  final Widget child;
  final int unread;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(CupertinoIcons.chat_bubble,
              size: 18, color: context.secondaryText),
          const SizedBox(width: 8),
          Expanded(child: child),
          if (unread > 0) _UnreadBadge(count: unread),
          if (showChevron) ...[
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_right,
                size: 14, color: context.secondaryText),
          ],
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: CupertinoColors.systemRed.resolveFrom(context),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: CupertinoColors.white,
        ),
      ),
    );
  }
}
