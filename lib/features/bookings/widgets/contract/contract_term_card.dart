import 'package:flutter/cupertino.dart';

import '../../data/models/contract_term.dart';

class ContractTermCard extends StatelessWidget {
  const ContractTermCard({
    super.key,
    required this.term,
    required this.editMode,
    required this.onTitleChanged,
    required this.onContentChanged,
    required this.dragHandle,
  });

  final ContractTerm term;
  final bool editMode;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onContentChanged;
  final Widget dragHandle;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('contract-term-${term.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: editMode
            ? CupertinoColors.systemGrey6.resolveFrom(context)
            : CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CupertinoColors.separator.resolveFrom(context),
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        child: editMode ? _buildEdit(context) : _buildPreview(context),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    return Column(
      key: const ValueKey('preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          term.title.isEmpty ? '(Untitled section)' : term.title.toUpperCase(),
          style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                decoration: TextDecoration.underline,
              ),
        ),
        const SizedBox(height: 6),
        Text(term.content),
      ],
    );
  }

  Widget _buildEdit(BuildContext context) {
    return Row(
      key: const ValueKey('edit'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, right: 8),
          child: dragHandle,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CupertinoTextField(
                controller: TextEditingController(text: term.title)
                  ..selection =
                      TextSelection.collapsed(offset: term.title.length),
                placeholder: 'Section Title',
                onChanged: onTitleChanged,
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: TextEditingController(text: term.content)
                  ..selection =
                      TextSelection.collapsed(offset: term.content.length),
                placeholder: 'Terms and conditions...',
                maxLines: null,
                minLines: 3,
                onChanged: onContentChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
