import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../../data/pasted_questionnaires.dart';

/// Full-screen sheet for one pasted questionnaire block: its answers grouped
/// by `== Section ==` header into collapsible groups, plus (for writers) a
/// destructive "Remove pasted text from notes" action.
class PastedQuestionnaireSheet extends StatefulWidget {
  const PastedQuestionnaireSheet({
    super.key,
    required this.block,
    this.onRemove,
  });

  final PastedQuestionnaire block;

  /// Removes this block from the event notes. Null hides the action (read-only
  /// viewers).
  final Future<void> Function()? onRemove;

  @override
  State<PastedQuestionnaireSheet> createState() =>
      _PastedQuestionnaireSheetState();
}

class _PastedQuestionnaireSheetState extends State<PastedQuestionnaireSheet> {
  bool _removing = false;

  Future<void> _confirmRemove() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Remove pasted text?'),
        content: const Text(
          'This deletes the pasted answers from the event notes. '
          'It cannot be undone.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _removing = true);
    try {
      await widget.onRemove!();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _removing = false);
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Could not remove'),
          content: Text(ErrorView.friendlyMessage(e)),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final single = block.sections.length == 1;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Client answers'),
        automaticallyImplyLeading: false,
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              block.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '${block.date} · ${block.answerCount} answers',
              style: TextStyle(fontSize: 13, color: context.secondaryText),
            ),
            const SizedBox(height: 16),
            if (block.sections.isEmpty)
              Text(
                'No answers in this block.',
                style: TextStyle(fontSize: 15, color: context.secondaryText),
              ),
            for (final s in block.sections) ...[
              _SectionGroup(section: s, initiallyExpanded: single),
              const SizedBox(height: 8),
            ],
            if (widget.onRemove != null) ...[
              const SizedBox(height: 16),
              CupertinoButton(
                onPressed: _removing ? null : _confirmRemove,
                child: _removing
                    ? const CupertinoActivityIndicator()
                    : Text(
                        'Remove pasted text from notes',
                        style: TextStyle(
                          color: CupertinoColors.destructiveRed
                              .resolveFrom(context),
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One collapsible `== Section ==` group.
class _SectionGroup extends StatefulWidget {
  const _SectionGroup({required this.section, required this.initiallyExpanded});
  final PastedSection section;
  final bool initiallyExpanded;

  @override
  State<_SectionGroup> createState() => _SectionGroupState();
}

class _SectionGroupState extends State<_SectionGroup> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: s.label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.label,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${s.lines.length}',
                        style: TextStyle(
                            fontSize: 13, color: context.secondaryText),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _expanded
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        size: 14,
                        color: context.tertiaryText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_expanded)
            for (final line in s.lines)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: _AnswerLine(line: line),
              ),
        ],
      ),
    );
  }
}

/// "Label: value" rendered as a small label above the value; lines without a
/// label are shown as-is.
class _AnswerLine extends StatelessWidget {
  const _AnswerLine({required this.line});
  final String line;

  @override
  Widget build(BuildContext context) {
    final idx = line.indexOf(':');
    if (idx <= 0 || idx == line.length - 1) {
      return Text(line, style: const TextStyle(fontSize: 15));
    }
    final label = line.substring(0, idx).trim();
    final value = line.substring(idx + 1).trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: context.secondaryText)),
        const SizedBox(height: 1),
        Text(value, style: const TextStyle(fontSize: 15)),
      ],
    );
  }
}
