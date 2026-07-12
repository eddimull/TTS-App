import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/widgets/auth_thumbnail.dart';
import '../../../shared/widgets/error_view.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_message.dart';
import '../providers/chat_thread_provider.dart';

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
  final List<XFile> _pendingImages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatThreadProvider(widget.conversationId).notifier).load();
    });
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <= 40) {
      ref.read(chatThreadProvider(widget.conversationId).notifier).loadMore();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickImages() async {
    // image_picker downscales/compresses on-device; no extra package needed.
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 80,
      maxWidth: 2048,
      limit: 4,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _pendingImages
        ..clear()
        ..addAll(picked.take(4));
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingImages.isEmpty) return;
    final uploads = <ChatImageUpload>[
      for (final x in _pendingImages)
        ChatImageUpload(bytes: await x.readAsBytes(), filename: x.name),
    ];
    _controller.clear();
    setState(() => _pendingImages.clear());
    await ref
        .read(chatThreadProvider(widget.conversationId).notifier)
        .send(text: text, images: uploads);
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final auth = ref.read(authProvider).value;
    final currentUserId =
        auth is AuthAuthenticated ? auth.user.id : null;
    final state = ref.read(chatThreadProvider(widget.conversationId));
    final isOwn = message.userId == currentUserId;
    final canModerate = state.conversation?.canModerate ?? false;
    if (message.isDeleted || (!isOwn && !canModerate)) return;

    final notifier =
        ref.read(chatThreadProvider(widget.conversationId).notifier);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          if (isOwn && message.attachments.isEmpty)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                _showEditDialog(message);
              },
              child: const Text('Edit'),
            ),
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
      final grew = previous == null ||
          next.messages.length != previous.messages.length;
      if (grew) _scrollToBottom();
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
                      padding: const EdgeInsets.all(12),
                      itemCount:
                          state.messages.length + (state.isLoadingMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (state.isLoadingMore && i == 0) {
                          return const Padding(
                            padding: EdgeInsets.all(8),
                            child: Center(child: CupertinoActivityIndicator()),
                          );
                        }
                        final idx = state.isLoadingMore ? i - 1 : i;
                        final message = state.messages[idx];
                        final isLast = idx == state.messages.length - 1;
                        return _MessageBubble(
                          message: message,
                          isOwn: message.userId == currentUserId,
                          showSeen: isLast &&
                              message.userId == currentUserId &&
                              seenByOthersCount(message, state.participants,
                                      currentUserId) >
                                  0,
                          isDm: state.conversation?.type == 'dm',
                          onLongPress: () => _showMessageActions(message),
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
                                child: FutureBuilder(
                                  future: img.readAsBytes(),
                                  builder: (_, snap) => snap.hasData
                                      ? Image.memory(snap.data!,
                                          fit: BoxFit.cover)
                                      : const CupertinoActivityIndicator(),
                                ),
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

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    required this.isOwn,
    required this.showSeen,
    required this.isDm,
    required this.onLongPress,
  });

  final ChatMessage message;
  final bool isOwn;
  final bool showSeen;
  final bool isDm;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(chatRepositoryProvider);
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
                for (final attachment in message.attachments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
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
                if (message.editedAt != null && !message.isDeleted)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'edited',
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
        if (showSeen)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              'Seen',
              style: TextStyle(fontSize: 11, color: context.tertiaryText),
            ),
          ),
      ],
    );
  }
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
