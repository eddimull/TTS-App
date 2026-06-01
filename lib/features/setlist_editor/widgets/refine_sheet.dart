import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/setlist_editor_provider.dart';

// ── Chat turn model ────────────────────────────────────────────────────────────

/// Represents one message in the refine chat thread.
/// [role] must be 'user' or 'assistant' — matches backend validation.
class RefineChatTurn {
  const RefineChatTurn(this.role, this.content);
  final String role; // 'user' | 'assistant'
  final String content;
}

// ── Public API ─────────────────────────────────────────────────────────────────

/// Opens the AI refine chat sheet as a Cupertino modal popup.
///
/// [eventKey] — the event key that identifies which [setlistEditorProvider]
/// family member to read/write. Task 16 (SetlistEditorScreen) calls this.
///
/// Returns a Future that resolves when the sheet is dismissed.
Future<void> showRefineSheet(
  BuildContext context, {
  required String eventKey,
}) {
  // showCupertinoModalPopup creates a new route with a fresh widget tree, so
  // the ProviderScope ancestor is lost. Re-attach the existing container via
  // UncontrolledProviderScope so the sheet shares the same notifier instances.
  final container = ProviderScope.containerOf(context);
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: _RefineSheet(eventKey: eventKey),
    ),
  );
}

// ── Widget ─────────────────────────────────────────────────────────────────────

class _RefineSheet extends ConsumerStatefulWidget {
  const _RefineSheet({required this.eventKey});
  final String eventKey;

  @override
  ConsumerState<_RefineSheet> createState() => _RefineSheetState();
}

class _RefineSheetState extends ConsumerState<_RefineSheet> {
  final _msg = TextEditingController();
  final _scroll = ScrollController();

  /// Full conversation history accumulated in this sheet session.
  final List<RefineChatTurn> _history = [];

  @override
  void dispose() {
    _msg.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msg.text.trim();
    if (text.isEmpty) return;

    // Append the user turn before the network call so it appears immediately.
    setState(() {
      _history.add(RefineChatTurn('user', text));
      _msg.clear();
    });
    _scrollToBottom();

    // Build the prior-turns history slice (all turns before the new user
    // message, i.e. everything except the last element we just appended).
    final priorHistory = _history
        .take(_history.length - 1)
        .map((t) => {'role': t.role, 'content': t.content})
        .toList();

    final result = await ref
        .read(setlistEditorProvider(widget.eventKey).notifier)
        .refine(text, history: priorHistory);

    // Whether ok or not, the returned summary goes into the chat as an
    // assistant bubble — failures show the friendly error message there
    // rather than a global banner (per notifier contract).
    setState(() {
      _history.add(RefineChatTurn('assistant', result.summary));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRefining =
        ref.watch(setlistEditorProvider(widget.eventKey)).isRefining;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      // Shift up when the keyboard appears.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            const Text(
              'Refine Setlist',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Expanded(child: _chatArea(context, isRefining)),
            _inputBar(context, isRefining),
          ],
        ),
      ),
    );
  }

  Widget _chatArea(BuildContext context, bool isRefining) {
    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Describe what you\'d like to change.\n\n'
            'Example: "Swap song 3 for something more upbeat"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      );
    }

    // Add a synthetic spinner item at the end while the AI is working.
    final itemCount = _history.length + (isRefining ? 1 : 0);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: itemCount,
      itemBuilder: (_, i) {
        if (i == _history.length) {
          // Spinner bubble shown while isRefining.
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                CupertinoActivityIndicator(),
                SizedBox(width: 8),
                Text(
                  'AI is refining…',
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          );
        }

        final turn = _history[i];
        final isUser = turn.role == 'user';

        return Align(
          alignment:
              isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              // Cap bubble width at 75 % of screen width (works 320 px–1200 px).
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isUser
                  ? CupertinoColors.activeBlue
                  : CupertinoColors.systemGrey6.resolveFrom(context),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              turn.content,
              style: TextStyle(
                fontSize: 14,
                color: isUser
                    ? CupertinoColors.white
                    : CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _inputBar(BuildContext context, bool isRefining) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: _msg,
              placeholder: 'What would you like to change?',
              padding: const EdgeInsets.all(10),
              maxLines: 3,
              minLines: 1,
              // Disable input while the AI call is in flight.
              enabled: !isRefining,
            ),
          ),
          const SizedBox(width: 8),
          // Send button: null onPressed acts as disabled in Cupertino style.
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            onPressed: isRefining ? null : _send,
            child: const Icon(
              CupertinoIcons.arrow_up_circle_fill,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}
