import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Material, MaterialType, ReorderableListView, ReorderableDragStartListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../providers/questionnaire_editor_provider.dart';
import '../providers/questionnaires_provider.dart';
import 'field_editor_screen.dart';
import 'questionnaire_preview_screen.dart';

class QuestionnaireEditorScreen extends ConsumerStatefulWidget {
  const QuestionnaireEditorScreen({super.key, required this.questionnaireId});

  final int questionnaireId;

  @override
  ConsumerState<QuestionnaireEditorScreen> createState() =>
      _QuestionnaireEditorScreenState();
}

class _QuestionnaireEditorScreenState
    extends ConsumerState<QuestionnaireEditorScreen> {
  TextEditingController? _name;
  TextEditingController? _description;
  bool _saving = false;

  static const _navBar = CupertinoNavigationBar(
    middle: Text('Edit Questionnaire'),
  );

  @override
  void dispose() {
    _name?.dispose();
    _description?.dispose();
    super.dispose();
  }

  ({int bandId, int questionnaireId})? get _key {
    final bandId = ref.read(selectedBandProvider).value;
    if (bandId == null) return null;
    return (bandId: bandId, questionnaireId: widget.questionnaireId);
  }

  @override
  Widget build(BuildContext context) {
    final bandId = ref.watch(selectedBandProvider).value;

    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: _navBar,
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    final key = (bandId: bandId, questionnaireId: widget.questionnaireId);
    final editorAsync = ref.watch(questionnaireEditorProvider(key));

    if (editorAsync.isLoading && !editorAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: _navBar,
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    if (editorAsync.hasError && !editorAsync.hasValue) {
      return CupertinoPageScaffold(
        navigationBar: _navBar,
        child: SafeArea(
          child: Center(
            child: Text(
              'Failed to load questionnaire.',
              style: TextStyle(color: context.secondaryText),
            ),
          ),
        ),
      );
    }

    final state = editorAsync.value!;
    final notifier = ref.read(questionnaireEditorProvider(key).notifier);

    // Controllers are created once from the loaded state, then own the text.
    _name ??= TextEditingController(text: state.name);
    _description ??= TextEditingController(text: state.description ?? '');

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        // ignore: use_build_context_synchronously
        if (discard && mounted) Navigator.of(context).pop();
      },
      child: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: const Text('Edit Questionnaire'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _openPreview(state),
                child: const Icon(CupertinoIcons.eye, size: 22),
              ),
              CupertinoButton(
                padding: const EdgeInsets.only(left: 8),
                onPressed:
                    state.dirty && !_saving ? () => _save(notifier) : null,
                child: _saving
                    ? const CupertinoActivityIndicator()
                    : const Text('Save'),
              ),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CupertinoTextField(
                      controller: _name,
                      placeholder: 'Name',
                      onChanged: notifier.setName,
                    ),
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      controller: _description,
                      placeholder: 'Description (optional)',
                      minLines: 1,
                      maxLines: 3,
                      onChanged: (v) =>
                          notifier.setDescription(v.isEmpty ? null : v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: state.fields.isEmpty
                    ? Center(
                        child: Text(
                          'No fields yet. Add one below.',
                          style: TextStyle(color: context.secondaryText),
                        ),
                      )
                    // ReorderableListView is Material-only; wrap with a
                    // transparent Material so no ink bleeds onto Cupertino.
                    : Material(
                        type: MaterialType.transparency,
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: state.fields.length,
                          onReorder: notifier.reorder,
                          itemBuilder: (_, i) => _FieldRow(
                            key: ValueKey(state.fields[i].clientId),
                            field: state.fields[i],
                            index: i,
                            onTap: () => _openFieldEditor(state, i),
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: CupertinoButton.filled(
                  onPressed: _addField,
                  child: const Text('Add field'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(QuestionnaireEditorNotifier notifier) async {
    setState(() => _saving = true);
    try {
      await notifier.save();
    } catch (_) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        await showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Save failed'),
            content: const Text(
                'Check that every field has a label and choice fields have options.'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _addField() async {
    final key = _key;
    if (key == null) return;
    final catalog =
        await ref.read(questionnaireCatalogProvider(key.bandId).future);
    if (!mounted) return;

    final inputTypes = catalog.fieldTypes.where((t) => t.isInput).toList();
    final displayTypes = catalog.fieldTypes.where((t) => !t.isInput).toList();

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Add field'),
        actions: [
          for (final t in [...inputTypes, ...displayTypes])
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                final notifier =
                    ref.read(questionnaireEditorProvider(key).notifier);
                notifier.addField(t.type);
                final state =
                    ref.read(questionnaireEditorProvider(key)).value!;
                _openFieldEditor(state, state.fields.length - 1);
              },
              child: Text(t.isInput ? t.label : '${t.label} (display)'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _openFieldEditor(QuestionnaireEditorState state, int index) {
    final key = _key;
    if (key == null) return;
    final field = state.fields[index];
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => FieldEditorScreen(
          bandId: key.bandId,
          clientId: field.clientId,
          editorKey: key,
        ),
      ),
    );
    // FieldEditorScreen reads/writes the editor provider directly by clientId,
    // so no callbacks are needed and it survives provider refreshes.
  }

  void _openPreview(QuestionnaireEditorState state) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => QuestionnairePreviewScreen(
          title: state.name,
          fields: state.fields,
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.field,
    required this.index,
    required this.onTap,
  });

  final EditorField field;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if (field.options.isNotEmpty) '${field.options.length} options',
      if (field.visibilityRule != null) 'conditional',
      if (field.mappingTarget != null) 'mapped',
    ];

    return CupertinoListTile(
      leading: ReorderableDragStartListener(
        index: index,
        child: Icon(CupertinoIcons.line_horizontal_3,
            size: 20, color: context.secondaryText),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              field.label.isEmpty ? '(untitled)' : field.label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (field.required)
            const Text(' *',
                style: TextStyle(color: CupertinoColors.destructiveRed)),
        ],
      ),
      subtitle: Text(
        chips.isEmpty ? field.type : '${field.type} · ${chips.join(' · ')}',
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }
}
