import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        DefaultMaterialLocalizations,
        Dismissible,
        DismissDirection,
        ReorderableDragStartListener,
        ReorderableListView;

import '../../data/models/contract_term.dart';
import 'contract_term_card.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

typedef TermFieldCb = void Function(int id, String value);

class ContractTermsList extends StatelessWidget {
  const ContractTermsList({
    super.key,
    required this.terms,
    required this.editMode,
    required this.onTitleChanged,
    required this.onContentChanged,
    required this.onAddSection,
    required this.onRemoveSection,
    required this.onReorder,
  });

  final List<ContractTerm> terms;
  final bool editMode;
  final TermFieldCb onTitleChanged;
  final TermFieldCb onContentChanged;
  final VoidCallback onAddSection;
  final ValueChanged<int> onRemoveSection;
  final void Function(int oldIndex, int newIndex) onReorder;

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete section?'),
        content: const Text('This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    if (terms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              editMode
                  ? 'No terms yet — tap Add Section to begin.'
                  : 'No terms yet.',
              style: CupertinoTheme.of(context)
                  .textTheme
                  .textStyle
                  .copyWith(color: context.secondaryText),
              textAlign: TextAlign.center,
            ),
            if (editMode) ...[
              const SizedBox(height: 12),
              CupertinoButton.filled(
                onPressed: onAddSection,
                child: const Text('Add Section'),
              ),
            ],
          ],
        ),
      );
    }

    if (!editMode) {
      return Column(
        children: [
          for (final t in terms)
            ContractTermCard(
              term: t,
              editMode: false,
              onTitleChanged: (_) {},
              onContentChanged: (_) {},
              dragHandle: const SizedBox.shrink(),
            ),
        ],
      );
    }

    return Column(
      children: [
        // ReorderableListView requires MaterialLocalizations. Provide the
        // default delegate so the widget works inside a CupertinoApp without
        // adding flutter_localizations / MaterialApp at the root.
        Localizations.override(
          context: context,
          delegates: const [DefaultMaterialLocalizations.delegate],
          // shrink-wrapped, non-scrolling: the outer page scroll owns scrolling.
          child: ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: terms.length,
            onReorder: onReorder,
            itemBuilder: (ctx, i) {
              final t = terms[i];
              return Dismissible(
                key: ValueKey('dismiss-${t.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: CupertinoColors.systemRed.resolveFrom(ctx),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(CupertinoIcons.delete,
                      color: CupertinoColors.white),
                ),
                confirmDismiss: (_) => _confirmDelete(ctx),
                onDismissed: (_) => onRemoveSection(t.id),
                child: ContractTermCard(
                  term: t,
                  editMode: true,
                  onTitleChanged: (v) => onTitleChanged(t.id, v),
                  onContentChanged: (v) => onContentChanged(t.id, v),
                  dragHandle: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(
                      CupertinoIcons.line_horizontal_3,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        CupertinoButton(
          onPressed: onAddSection,
          child: const Text('Add Section'),
        ),
      ],
    );
  }
}
