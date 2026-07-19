import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/widgets/auth_thumbnail.dart';
import '../../../shared/widgets/error_view.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_message.dart';
import '../providers/active_chat_conversation_provider.dart';
import '../providers/chat_thread_provider.dart';
import '../utils/message_time.dart';
import 'attachment_viewer_screen.dart';

/// The fixed tapback set (spec phase 2); extendable to a full picker later.
const kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🎉', '🖕'];

/// A picked-but-not-yet-sent image. Bytes are read once at pick time (not
/// re-read from disk on every rebuild via a FutureBuilder) so the thumbnail
/// strip and the eventual upload share the same in-memory copy.
class _PendingImage {
  const _PendingImage({required this.file, required this.bytes});
  final XFile file;
  final Uint8List bytes;
}

class ConversationThreadScreen extends ConsumerStatefulWidget {
  const ConversationThreadScreen({
    super.key,
    required this.conversationId,
    this.title,
  });

  final int conversationId;
  final String? title;

  @override
  ConsumerState<ConversationThreadScreen> createState() =>
      _ConversationThreadScreenState();
}

class _ConversationThreadScreenState
    extends ConsumerState<ConversationThreadScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_PendingImage> _pendingImages = [];
  final Set<int> _revealedTimeIds = {};

  // The list is built with `reverse: true` (see build()): rendered item 0 is
  // the newest message and sits at the bottom of the viewport, with scroll
  // offset 0 meaning "pinned to the newest message". This gives two things
  // for free that the old forward-ordered ListView had to hand-roll (badly):
  //   - Appending a new message at the end of `state.messages` (reversed ->
  //     item 0) is a no-op for the viewport's pixel position, so an
  //     already-at-bottom reader stays pinned to the new message without any
  //     animateTo call.
  //   - Prepending older messages (loadMore) appends them at the *end* of the
  //     reversed list, i.e. off the bottom of what's currently rendered —
  //     existing on-screen items don't shift, so history loads without
  //     yanking the viewport.
  // The one thing reverse:true does NOT give for free is the very first
  // frame: a ListView starts at scroll offset 0 by construction, which here
  // already *is* "pinned to the newest message" — no jumpTo/animateTo is
  // needed at all for the initial open.
  bool _loadMoreArmed = false;

  // Captured in initState (while `ref` is still safe to read) so dispose()
  // can clear the marker without touching `ref` after the widget has been
  // unmounted — Riverpod disallows `ref.read` inside State.dispose() because
  // BuildContext (which Ref relies on) is unsafe once deactivated.
  late final ActiveChatConversationNotifier _activeConversationNotifier;

  @override
  void initState() {
    super.initState();
    _activeConversationNotifier =
        ref.read(activeChatConversationProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(chatThreadProvider(widget.conversationId).notifier).load();
      // Mark this thread as the one on screen so PushService can suppress a
      // local notification for messages that arrive in it while it's open.
      // Deferred to post-frame to avoid modifying a provider during build.
      _activeConversationNotifier.open(widget.conversationId);
    });
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    // Only clears the "active thread" marker if it still points at this
    // screen's own id — if another thread was pushed on top and became
    // active first, this dispose (running as we're popped from underneath)
    // must not clobber the newer screen's value. Deferred to a microtask:
    // Riverpod disallows modifying a provider synchronously while the widget
    // tree is still finalizing (which includes the dispose pass itself).
    final notifier = _activeConversationNotifier;
    final conversationId = widget.conversationId;
    Future.microtask(() => notifier.closeIfCurrent(conversationId));
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// In a reversed list, scrolling toward older history moves the offset
  /// *up* toward maxScrollExtent (the opposite edge from a normal list).
  /// [_loadMoreArmed] is only set true once the initial page has rendered
  /// (see build()), so the transient settle of the first frame — which starts
  /// at offset 0 by construction, not via any animation that could pass
  /// through the trigger threshold — can never itself fire a chain of
  /// loadMore() calls.
  void _maybeLoadMore() {
    if (!_loadMoreArmed || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <= 40) {
      ref.read(chatThreadProvider(widget.conversationId).notifier).loadMore();
    }
  }

  Future<void> _pickImages() async {
    // image_picker downscales/compresses on-device; no extra package needed.
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 80,
      maxWidth: 2048,
      limit: 4,
    );
    if (picked.isEmpty || !mounted) return;
    // Read each file's bytes once, up front, instead of leaving it to a
    // FutureBuilder in the thumbnail strip that would otherwise re-read from
    // disk on every rebuild (typing, send-button state changes, etc.).
    final pending = <_PendingImage>[
      for (final x in picked.take(4))
        _PendingImage(file: x, bytes: await x.readAsBytes()),
    ];
    if (!mounted) return;
    setState(() {
      _pendingImages
        ..clear()
        ..addAll(pending);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final images = List<_PendingImage>.of(_pendingImages);
    if (text.isEmpty && images.isEmpty) return;
    final uploads = <ChatImageUpload>[
      for (final img in images)
        ChatImageUpload(bytes: img.bytes, filename: img.file.name),
    ];
    _controller.clear();
    setState(() => _pendingImages.clear());
    await ref
        .read(chatThreadProvider(widget.conversationId).notifier)
        .send(text: text, images: uploads);
    if (!mounted) return;
    final error = ref.read(chatThreadProvider(widget.conversationId)).error;
    if (error != null) {
      // Send failed — restore what the user typed/picked so nothing is lost.
      setState(() {
        if (_controller.text.isEmpty) _controller.text = text;
        if (_pendingImages.isEmpty) _pendingImages.addAll(images);
      });
    }
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final auth = ref.read(authProvider).value;
    final currentUserId = auth is AuthAuthenticated ? auth.user.id : null;
    final state = ref.read(chatThreadProvider(widget.conversationId));
    final isOwn = message.userId == currentUserId;
    final canModerate = state.conversation?.canModerate ?? false;
    if (message.isDeleted || currentUserId == null) return;

    final notifier =
        ref.read(chatThreadProvider(widget.conversationId).notifier);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final emoji in kQuickReactions)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  notifier.toggleReaction(message.id, emoji, currentUserId);
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: message.reactions.any((r) =>
                            r.emoji == emoji && r.reactedBy(currentUserId))
                        ? CupertinoColors.activeBlue
                            .resolveFrom(sheetContext)
                            .withValues(alpha: 0.25)
                        : null,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              ),
          ],
        ),
        actions: [
          if (isOwn && message.attachments.isEmpty)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                _showEditDialog(message);
              },
              child: const Text('Edit'),
            ),
          if (isOwn || canModerate)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(sheetContext);
                notifier.deleteMsg(message.id);
              },
              child: const Text('Delete'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showSeenByNames(List<String> names) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Seen by'),
        message: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final name in names)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    color: context.primaryText,
                  ),
                ),
              ),
          ],
        ),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _showEditDialog(ChatMessage message) async {
    final editController = TextEditingController(text: message.body);
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Edit message'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(controller: editController, maxLines: null),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final text = editController.text.trim();
              Navigator.pop(dialogContext);
              if (text.isNotEmpty && text != message.body) {
                ref
                    .read(chatThreadProvider(widget.conversationId).notifier)
                    .editMsg(message.id, text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatThreadProvider(widget.conversationId), (previous, next) {
      // Arm the top-of-history (loadMore) trigger only once the thread has
      // rendered its first page — never while messages is still empty, so
      // the initial frame can't itself chain-fetch. A programmatic loadMore
      // prepend changes hasMore/isLoadingMore but never the newest message,
      // so gating on the last message id changing here would work equally
      // well; arming once on first non-empty state is simpler and just as
      // safe since _maybeLoadMore's own threshold check does the real work
      // on every subsequent scroll notification.
      if (!_loadMoreArmed && next.messages.isNotEmpty) {
        _loadMoreArmed = true;
      }
    });

    final state = ref.watch(chatThreadProvider(widget.conversationId));
    final auth = ref.watch(authProvider).value;
    final currentUserId = auth is AuthAuthenticated ? auth.user.id : -1;
    final title = widget.title ?? state.conversation?.title ?? 'Conversation';

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(title)),
      child: SafeArea(
        child: Column(
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  ErrorView.friendlyMessage(state.error!),
                  style: TextStyle(
                      color: CupertinoColors.systemRed.resolveFrom(context)),
                ),
              ),
            Expanded(
              child: state.isLoading && state.messages.isEmpty
                  ? const Center(child: CupertinoActivityIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount:
                          state.messages.length + (state.isLoadingMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        // Reversed rendering: item 0 is the newest message
                        // (bottom of the viewport); the loading-more spinner
                        // for older history sits at the opposite end (the
                        // highest index), not index 0.
                        if (state.isLoadingMore &&
                            i == state.messages.length) {
                          return const Padding(
                            padding: EdgeInsets.all(8),
                            child: Center(child: CupertinoActivityIndicator()),
                          );
                        }
                        final idx = state.messages.length - 1 - i;
                        final message = state.messages[idx];
                        final previous =
                            idx > 0 ? state.messages[idx - 1] : null;
                        final isLast = idx == state.messages.length - 1;
                        final isDm = state.conversation?.type == 'dm';
                        Widget? status;
                        if (isLast && message.userId == currentUserId) {
                          if (isDm) {
                            final other = state.participants
                                .where((p) => p.userId != currentUserId)
                                .toList();
                            switch (dmMessageStatus(
                                message, state.participants, currentUserId)) {
                              case DmMessageStatus.seen:
                                // dmMessageStatus returns `seen` if ANY other
                                // participant's read receipt qualifies; pick
                                // that same qualifying participant's
                                // lastReadAt rather than assuming it's
                                // other.first (they can disagree in a
                                // >2-participant 'dm').
                                final qualifying = other.where((p) =>
                                    p.lastReadAt != null &&
                                    !p.lastReadAt!.isBefore(message.createdAt));
                                final at = qualifying.isEmpty
                                    ? null
                                    : qualifying.first.lastReadAt;
                                status = _StatusLabel(
                                  text: at == null
                                      ? 'Seen'
                                      : 'Seen ${bubbleTimeLabel(at, now: DateTime.now())}',
                                );
                              case DmMessageStatus.delivered:
                                status = const _StatusLabel(text: 'Delivered');
                              case DmMessageStatus.none:
                                status = null;
                            }
                          } else {
                            final names = seenByNames(
                                message, state.participants, currentUserId);
                            if (names.isNotEmpty) {
                              status = _StatusLabel(
                                text: 'Seen by ${names.length}',
                                onTap: () => _showSeenByNames(names),
                              );
                            }
                          }
                        }
                        final bubble = _MessageBubble(
                          message: message,
                          isOwn: message.userId == currentUserId,
                          currentUserId: currentUserId,
                          status: status,
                          isDm: isDm,
                          showTime: _revealedTimeIds.contains(message.id),
                          onTap: () => setState(() {
                            if (!_revealedTimeIds.remove(message.id)) {
                              _revealedTimeIds.add(message.id);
                            }
                          }),
                          onLongPress: () => _showMessageActions(message),
                        );
                        if (!needsDateSeparator(
                            previous?.createdAt, message.createdAt)) {
                          return bubble;
                        }
                        // stretch so the bubble Column keeps the full row
                        // width its own start/end alignment relies on.
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _DateSeparator(
                              label: dateSeparatorLabel(message.createdAt,
                                  now: DateTime.now()),
                            ),
                            bubble,
                          ],
                        );
                      },
                    ),
            ),
            if (state.typingUsers.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    state.typingUsers.length == 1
                        ? '${state.typingUsers.values.first} is typing…'
                        : 'Several people are typing…',
                    style: TextStyle(fontSize: 13, color: context.secondaryText),
                  ),
                ),
              ),
            if (_pendingImages.isNotEmpty)
              SizedBox(
                height: 64,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final img in _pendingImages)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: Image.memory(img.bytes,
                                    fit: BoxFit.cover),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _pendingImages.remove(img)),
                                child: const Icon(
                                    CupertinoIcons.xmark_circle_fill,
                                    size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            _Composer(
              controller: _controller,
              isBusy: state.isSending,
              onSend: _send,
              onPickImages: _pickImages,
              onChanged: (_) => ref
                  .read(chatThreadProvider(widget.conversationId).notifier)
                  .notifyTyping(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: context.secondaryText),
          ),
        ),
      );
}

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    required this.isOwn,
    required this.currentUserId,
    required this.status,
    required this.isDm,
    required this.showTime,
    required this.onTap,
    required this.onLongPress,
  });

  final ChatMessage message;
  final bool isOwn;
  final int currentUserId;
  final Widget? status;
  final bool isDm;
  final bool showTime;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(chatRepositoryProvider);
    final time = bubbleTimeLabel(message.createdAt, now: DateTime.now());
    final timeLabel = message.editedAt != null && !message.isDeleted
        ? '$time · edited'
        : time;
    return Column(
      crossAxisAlignment:
          isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isOwn && !isDm)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              message.userName,
              style: TextStyle(fontSize: 12, color: context.secondaryText),
            ),
          ),
        GestureDetector(
          onTap: onTap,
          onLongPress: message.isDeleted ? null : onLongPress,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8),
            decoration: BoxDecoration(
              color: message.isDeleted
                  ? CupertinoColors.secondarySystemBackground
                      .resolveFrom(context)
                  : isOwn
                      ? CupertinoColors.activeBlue.resolveFrom(context)
                      : CupertinoColors.tertiarySystemBackground
                          .resolveFrom(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, attachment)
                    in message.attachments.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => AttachmentViewerScreen(
                            messageId: message.id,
                            attachments: message.attachments,
                            initialIndex: index,
                          ),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 200,
                          height: attachment.width > 0
                              ? 200 * attachment.height / attachment.width
                              : 200,
                          child: AuthThumbnail(
                            url: repo.attachmentUrl(message.id, attachment.id),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (message.isDeleted)
                  Text(
                    'Message deleted',
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: context.tertiaryText,
                    ),
                  )
                else if (message.body.isNotEmpty)
                  Text(
                    message.body,
                    style: TextStyle(
                      fontSize: 15,
                      color: isOwn ? CupertinoColors.white : context.primaryText,
                    ),
                  ),
                if (showTime)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      timeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: isOwn
                            ? CupertinoColors.white.withValues(alpha: 0.7)
                            : context.tertiaryText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (message.reactions.isNotEmpty && !message.isDeleted)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              spacing: 4,
              children: [
                for (final reaction in message.reactions)
                  GestureDetector(
                    onTap: () => ref
                        .read(chatThreadProvider(message.conversationId)
                            .notifier)
                        .toggleReaction(
                            message.id, reaction.emoji, currentUserId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: reaction.reactedBy(currentUserId)
                            ? CupertinoColors.activeBlue
                                .resolveFrom(context)
                                .withValues(alpha: 0.25)
                            : CupertinoColors.tertiarySystemBackground
                                .resolveFrom(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${reaction.emoji} ${reaction.count}',
                        style: TextStyle(
                            fontSize: 13, color: context.primaryText),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: status,
          ),
      ],
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.text, this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Semantics(
          button: onTap != null,
          label: onTap != null ? '$text, tap to see who' : text,
          child: Text(
            text,
            style: TextStyle(fontSize: 11, color: context.tertiaryText),
          ),
        ),
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isBusy,
    required this.onSend,
    required this.onPickImages,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool isBusy;
  final VoidCallback onSend;
  final VoidCallback onPickImages;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: isBusy ? null : onPickImages,
            child: Icon(
              CupertinoIcons.photo,
              size: 24,
              color: context.secondaryText,
            ),
          ),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: 'Message…',
              maxLines: null,
              onChanged: onChanged,
              style: TextStyle(color: context.primaryText),
              placeholderStyle: TextStyle(color: context.placeholderText),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: isBusy ? null : onSend,
            child: isBusy
                ? const CupertinoActivityIndicator()
                : Icon(
                    CupertinoIcons.arrow_up_circle_fill,
                    size: 28,
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                  ),
          ),
        ],
      ),
    );
  }
}
