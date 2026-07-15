import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/questionnaire_catalog.dart';
import '../providers/questionnaires_provider.dart';

class CreateQuestionnaireSheet extends ConsumerStatefulWidget {
  const CreateQuestionnaireSheet({super.key, required this.bandId});

  final int bandId;

  @override
  ConsumerState<CreateQuestionnaireSheet> createState() =>
      _CreateQuestionnaireSheetState();
}

class _CreateQuestionnaireSheetState
    extends ConsumerState<CreateQuestionnaireSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  PresetDef? _preset;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created =
          await ref.read(questionnairesProvider(widget.bandId).notifier).create(
                name: _name.text.trim(),
                description: _description.text.trim().isEmpty
                    ? null
                    : _description.text.trim(),
                presetKey: _preset?.key,
              );
      if (mounted) {
        Navigator.of(context).pop();
        context.push('/questionnaires/${created.id}/edit');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to create questionnaire. Please try again.';
        });
      }
    }
  }

  Future<void> _pickPreset(List<PresetDef> presets) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Start from'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _preset = null);
              Navigator.of(sheetContext).pop();
            },
            child: const Text('Blank'),
          ),
          for (final p in presets)
            CupertinoActionSheetAction(
              onPressed: () {
                setState(() => _preset = p);
                Navigator.of(sheetContext).pop();
              },
              child: Text('${p.name} (${p.fieldCount} fields)'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(questionnaireCatalogProvider(widget.bandId));
    final presets = catalogAsync.value?.presets ?? const <PresetDef>[];

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Text('New Questionnaire',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const CupertinoActivityIndicator()
                        : const Text('Create'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _name,
                placeholder: 'Name',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _description,
                placeholder: 'Description (optional)',
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 8),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _saving ? null : () => _pickPreset(presets),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Start from'),
                    Text(
                      _preset?.name ?? 'Blank',
                      style: TextStyle(color: context.secondaryText),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                      color: CupertinoColors.destructiveRed, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
