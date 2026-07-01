import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/context_colors.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/models/planner_message.dart';
import '../data/models/planner_plan.dart';
import '../providers/rehearsal_planner_provider.dart';

class RehearsalPlannerScreen extends ConsumerWidget {
  const RehearsalPlannerScreen({
    super.key,
    required this.rehearsalId,
    this.rehearsalLabel,
    this.existingNotes,
  });

  /// The rehearsal this planner session is scoped to.
  final int rehearsalId;

  /// Optional human label (e.g. the rehearsal date) shown in the nav bar.
  final String? rehearsalLabel;

  /// The rehearsal's current notes, passed from the detail screen so the save
  /// flow can offer Append vs Replace. Null/empty means "no existing notes".
  final String? existingNotes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandAsync = ref.watch(selectedBandProvider);
    return bandAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar:
            CupertinoNavigationBar(middle: Text('Rehearsal Planner')),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => const CupertinoPageScaffold(
        navigationBar:
            CupertinoNavigationBar(middle: Text('Rehearsal Planner')),
        child: Center(child: Text('No band selected')),
      ),
      data: (bandId) {
        if (bandId == null) {
          return const CupertinoPageScaffold(
            navigationBar:
                CupertinoNavigationBar(middle: Text('Rehearsal Planner')),
            child: Center(child: Text('No band selected')),
          );
        }
        return _PlannerView(
          bandId: bandId,
          rehearsalId: rehearsalId,
          rehearsalLabel: rehearsalLabel,
          existingNotes: existingNotes,
        );
      },
    );
  }
}

class _PlannerView extends ConsumerStatefulWidget {
  const _PlannerView({
    required this.bandId,
    required this.rehearsalId,
    this.rehearsalLabel,
    this.existingNotes,
  });
  final int bandId;
  final int rehearsalId;
  final String? rehearsalLabel;
  final String? existingNotes;

  @override
  ConsumerState<_PlannerView> createState() => _PlannerViewState();
}

class _PlannerViewState extends ConsumerState<_PlannerView> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  PlannerArgs get _args =>
      PlannerArgs(bandId: widget.bandId, rehearsalId: widget.rehearsalId);

  Future<void> _onSavePlan(PlannerPlan plan) async {
    final notifier = ref.read(rehearsalPlannerProvider(_args).notifier);
    final existing = widget.existingNotes?.trim() ?? '';

    NotesSaveMode? mode;
    if (existing.isEmpty) {
      mode = NotesSaveMode.replace; // nothing to preserve → just write it
    } else {
      mode = await showCupertinoModalPopup<NotesSaveMode>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: const Text('Save plan to notes'),
          message: const Text('This rehearsal already has notes.'),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, NotesSaveMode.append),
              child: const Text('Append to notes'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(sheetContext, NotesSaveMode.replace),
              child: const Text('Replace notes'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('Cancel'),
          ),
        ),
      );
    }

    if (mode == null) return; // user cancelled
    if (!mounted) return;

    final ok = await notifier.savePlanToNotes(
      plan,
      mode: mode,
      existingNotes: widget.existingNotes,
    );
    if (ok && mounted) context.pop(true);
    // On failure the provider set state.error; the existing error banner shows it.
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rehearsalPlannerProvider(_args).notifier).start();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Auto-follow new messages and streaming text-delta growth, but skip
    // scrolling on unrelated state changes (e.g. isSending/error toggles).
    ref.listen(rehearsalPlannerProvider(_args), (previous, next) {
      final shouldScroll = previous == null ||
          next.messages.length != previous.messages.length ||
          (next.messages.isNotEmpty &&
              previous.messages.isNotEmpty &&
              next.messages.last.text != previous.messages.last.text);
      if (shouldScroll) _scrollToBottom();
    });

    final state = ref.watch(rehearsalPlannerProvider(_args));
    final notifier = ref.read(rehearsalPlannerProvider(_args).notifier);

    final title = widget.rehearsalLabel != null
        ? 'Plan: ${widget.rehearsalLabel}'
        : 'Rehearsal Planner';

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
                  style: TextStyle(color: CupertinoColors.systemRed.resolveFrom(context)),
                ),
              ),
            Expanded(
              child: state.isStarting && state.messages.isEmpty
                  ? const Center(child: CupertinoActivityIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: state.messages.length,
                      itemBuilder: (_, i) => _Bubble(
                        message: state.messages[i],
                        onSuggestionTap: (s) => notifier.send(s),
                        onRetry: notifier.retryLast,
                        isSavingPlan: state.isSavingPlan,
                        onSavePlan: _onSavePlan,
                      ),
                    ),
            ),
            _Composer(
              controller: _controller,
              isBusy: state.isSending,
              onSend: () {
                final text = _controller.text.trim();
                if (text.isEmpty || state.sessionId == null) return;
                _controller.clear();
                notifier.send(text);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.onSuggestionTap,
    required this.onRetry,
    required this.isSavingPlan,
    required this.onSavePlan,
  });

  final PlannerMessage message;
  final void Function(String) onSuggestionTap;
  final VoidCallback onRetry;
  final bool isSavingPlan;
  final Future<void> Function(PlannerPlan) onSavePlan;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isStreaming = message.status == 'streaming';
    final isFailed = message.status == 'failed';

    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          decoration: BoxDecoration(
            color: isUser
                ? CupertinoColors.activeBlue.resolveFrom(context)
                : CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: isStreaming && message.text.isEmpty
              ? const CupertinoActivityIndicator()
              : Text(
                  isFailed ? 'Failed to respond.' : message.text,
                  style: TextStyle(
                    color: isUser ? CupertinoColors.white : context.primaryText,
                    fontSize: 15,
                  ),
                ),
        ),
        if (isFailed)
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        if (message.plan != null)
          _PlanCard(
            plan: message.plan!,
            isSaving: isSavingPlan,
            onSave: () => onSavePlan(message.plan!),
          ),
        if (message.suggestions.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in message.suggestions)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => onSuggestionTap(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: CupertinoColors.activeBlue
                          .resolveFrom(context)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: CupertinoColors.activeBlue.resolveFrom(context),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        color: CupertinoColors.activeBlue.resolveFrom(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isSaving,
    required this.onSave,
  });
  final PlannerPlan plan;
  final bool isSaving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.title,
            style: TextStyle(fontWeight: FontWeight.w600, color: context.primaryText),
          ),
          const SizedBox(height: 6),
          for (final item in plan.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '• ${item.title} — ${item.reason}',
                style: TextStyle(fontSize: 14, color: context.secondaryText),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: CupertinoColors.activeBlue.resolveFrom(context),
              borderRadius: BorderRadius.circular(8),
              onPressed: isSaving ? null : onSave,
              child: isSaving
                  ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                  : const Text('Save to rehearsal notes',
                      style: TextStyle(color: CupertinoColors.white, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isBusy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isBusy;
  final VoidCallback onSend;

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
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: 'Ask the planner…',
              maxLines: null,
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
