import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/context_colors.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/models/planner_message.dart';
import '../providers/rehearsal_planner_provider.dart';

class RehearsalPlannerScreen extends ConsumerWidget {
  const RehearsalPlannerScreen({super.key});

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
        return _PlannerView(bandId: bandId);
      },
    );
  }
}

class _PlannerView extends ConsumerStatefulWidget {
  const _PlannerView({required this.bandId});
  final int bandId;

  @override
  ConsumerState<_PlannerView> createState() => _PlannerViewState();
}

class _PlannerViewState extends ConsumerState<_PlannerView> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rehearsalPlannerProvider(widget.bandId).notifier).start();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rehearsalPlannerProvider(widget.bandId));
    final notifier = ref.read(rehearsalPlannerProvider(widget.bandId).notifier);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Rehearsal Planner')),
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
                      padding: const EdgeInsets.all(12),
                      itemCount: state.messages.length,
                      itemBuilder: (_, i) => _Bubble(
                        message: state.messages[i],
                        onSuggestionTap: (s) => notifier.send(s),
                        onRetry: notifier.retryLast,
                      ),
                    ),
            ),
            _Composer(
              controller: _controller,
              isBusy: state.isSending,
              onSend: () {
                final text = _controller.text;
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
  });

  final PlannerMessage message;
  final void Function(String) onSuggestionTap;
  final VoidCallback onRetry;

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
        if (message.plan != null) _PlanCard(plan: message.plan!),
        if (message.suggestions.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final s in message.suggestions)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: CupertinoColors.systemGrey5.resolveFrom(context),
                  minimumSize: Size.zero,
                  onPressed: () => onSuggestionTap(s),
                  child: Text(s, style: TextStyle(color: context.primaryText, fontSize: 13)),
                ),
            ],
          ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});
  final dynamic plan; // PlannerPlan

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
            plan.title as String,
            style: TextStyle(fontWeight: FontWeight.w600, color: context.primaryText),
          ),
          const SizedBox(height: 6),
          for (final item in plan.items as Iterable)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '• ${item.title} — ${item.reason}',
                style: TextStyle(fontSize: 14, color: context.secondaryText),
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
