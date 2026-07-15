import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/questionnaire_catalog.dart';
import '../data/models/questionnaire_field.dart';
import '../providers/questionnaire_editor_provider.dart';
import '../providers/questionnaires_provider.dart';

class FieldEditorScreen extends ConsumerStatefulWidget {
  const FieldEditorScreen({
    super.key,
    required this.bandId,
    required this.clientId,
    required this.editorKey,
  });

  final int bandId;
  final String clientId;
  final ({int bandId, int questionnaireId}) editorKey;

  @override
  ConsumerState<FieldEditorScreen> createState() => _FieldEditorScreenState();
}

class _FieldEditorScreenState extends ConsumerState<FieldEditorScreen> {
  TextEditingController? _label;
  TextEditingController? _help;

  @override
  void dispose() {
    _label?.dispose();
    _help?.dispose();
    super.dispose();
  }

  EditorField? get _field {
    final state = ref.watch(questionnaireEditorProvider(widget.editorKey)).value;
    if (state == null) return null;
    for (final f in state.fields) {
      if (f.clientId == widget.clientId) return f;
    }
    return null;
  }

  QuestionnaireEditorNotifier get _notifier =>
      ref.read(questionnaireEditorProvider(widget.editorKey).notifier);

  void _apply(EditorField updated) => _notifier.updateField(updated);

  @override
  Widget build(BuildContext context) {
    final field = _field;
    final catalog =
        ref.watch(questionnaireCatalogProvider(widget.bandId)).value;

    if (field == null) {
      // Field was removed (e.g. via delete below) — nothing to edit.
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Field')),
        child: SafeArea(child: SizedBox.shrink()),
      );
    }

    _label ??= TextEditingController(text: field.label);
    _help ??= TextEditingController(text: field.helpText ?? '');

    final typeDef = catalog?.fieldTypes
        .where((t) => t.type == field.type)
        .firstOrNull;
    final isInput = typeDef?.isInput ?? true;
    final hasOptions =
        typeDef?.requiredSettings.contains('options') ?? false;
    final hasPurpose =
        typeDef?.requiredSettings.contains('purpose') ?? false;
    final compatibleTargets = (catalog?.mappingTargets ?? const <MappingTargetDef>[])
        .where((m) => m.compatibleFieldTypes.contains(field.type))
        .toList();
    final earlierFields = _earlierInputFields(field);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(typeDef?.label ?? field.type),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoTextFormFieldRow(
                  controller: _label,
                  prefix: const Text('Label'),
                  placeholder: 'Field label',
                  onChanged: (v) => _apply(field.copyWith(label: v)),
                ),
                CupertinoTextFormFieldRow(
                  controller: _help,
                  prefix: const Text('Help'),
                  placeholder: 'Optional help text',
                  onChanged: (v) => _apply(v.isEmpty
                      ? field.copyWith(clearHelpText: true)
                      : field.copyWith(helpText: v)),
                ),
                if (isInput)
                  CupertinoListTile(
                    title: const Text('Required'),
                    trailing: CupertinoSwitch(
                      value: field.required,
                      onChanged: (v) => _apply(field.copyWith(required: v)),
                    ),
                  ),
              ],
            ),
            if (hasOptions) _OptionsSection(field: field, onApply: _apply),
            if (hasPurpose)
              CupertinoListSection.insetGrouped(
                header: const Text('Song picker'),
                children: [
                  CupertinoListTile(
                    title: const Text('Purpose'),
                    additionalInfo: Text(_purposeLabel(
                        field.settings?['purpose'] as String? ?? 'general')),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => _pickPurpose(field),
                  ),
                ],
              ),
            if (compatibleTargets.isNotEmpty)
              CupertinoListSection.insetGrouped(
                header: const Text('Event mapping'),
                children: [
                  CupertinoListTile(
                    title: const Text('Maps to'),
                    additionalInfo: Text(
                      compatibleTargets
                              .where((m) => m.key == field.mappingTarget)
                              .firstOrNull
                              ?.label ??
                          'None',
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => _pickMappingTarget(field, compatibleTargets),
                  ),
                ],
              ),
            if (isInput && earlierFields.isNotEmpty)
              _VisibilitySection(
                field: field,
                earlierFields: earlierFields,
                onApply: _apply,
              ),
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoListTile(
                  title: const Text('Duplicate field'),
                  onTap: () {
                    _notifier.duplicateField(field.clientId);
                    Navigator.of(context).pop();
                  },
                ),
                CupertinoListTile(
                  title: const Text(
                    'Delete field',
                    style: TextStyle(color: CupertinoColors.destructiveRed),
                  ),
                  onTap: () {
                    _notifier.removeField(field.clientId);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Input fields positioned before this one — the only legal visibility
  /// dependencies (server enforces forward-only references).
  List<EditorField> _earlierInputFields(EditorField field) {
    final state =
        ref.read(questionnaireEditorProvider(widget.editorKey)).value;
    if (state == null) return const [];
    final index =
        state.fields.indexWhere((f) => f.clientId == field.clientId);
    if (index <= 0) return const [];
    return state.fields
        .sublist(0, index)
        .where((f) => f.type != 'header' && f.type != 'instructions')
        .toList();
  }

  String _purposeLabel(String purpose) {
    switch (purpose) {
      case 'must_play':
        return 'Must play';
      case 'do_not_play':
        return 'Do not play';
      default:
        return 'General';
    }
  }

  Future<void> _pickPurpose(EditorField field) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Purpose'),
        actions: [
          for (final purpose in const ['must_play', 'do_not_play', 'general'])
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _apply(field.copyWith(settings: {
                  ...?field.settings,
                  'purpose': purpose,
                }));
              },
              child: Text(_purposeLabel(purpose)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickMappingTarget(
      EditorField field, List<MappingTargetDef> targets) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Maps to'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _apply(field.copyWith(clearMappingTarget: true));
            },
            child: const Text('None'),
          ),
          for (final t in targets)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _apply(field.copyWith(mappingTarget: t.key));
              },
              child: Text(t.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

// ── Options editor ────────────────────────────────────────────────────────────

class _OptionsSection extends StatelessWidget {
  const _OptionsSection({required this.field, required this.onApply});

  final EditorField field;
  final ValueChanged<EditorField> onApply;

  void _setOptions(List<FieldOption> options) {
    onApply(field.copyWith(settings: {
      ...?field.settings,
      'options': options.map((o) => o.toJson()).toList(),
    }));
  }

  @override
  Widget build(BuildContext context) {
    final options = field.options;
    return CupertinoListSection.insetGrouped(
      header: const Text('Options'),
      children: [
        for (var i = 0; i < options.length; i++)
          CupertinoListTile(
            // Key on index+label so edits rebuild correctly.
            key: ValueKey('option-$i-${options[i].value}'),
            title: Text(options[i].label),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                final next = [...options]..removeAt(i);
                _setOptions(next);
              },
              child: const Icon(CupertinoIcons.minus_circle,
                  color: CupertinoColors.destructiveRed, size: 20),
            ),
            onTap: () => _editOption(context, options, i),
          ),
        CupertinoListTile(
          title: const Text('Add option'),
          leading: const Icon(CupertinoIcons.add_circled, size: 20),
          onTap: () => _editOption(context, options, null),
        ),
      ],
    );
  }

  Future<void> _editOption(
      BuildContext context, List<FieldOption> options, int? index) async {
    final controller =
        TextEditingController(text: index == null ? '' : options[index].label);
    final label = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(index == null ? 'Add option' : 'Edit option'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(controller: controller, autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.isEmpty) return;

    final next = [...options];
    if (index == null) {
      // New options use the label as the value (matching simple web usage);
      // existing options keep their stored value when relabeled.
      next.add(FieldOption(label: label, value: label));
    } else {
      next[index] = FieldOption(label: label, value: next[index].value);
    }
    _setOptions(next);
  }
}

// ── Visibility rule builder ───────────────────────────────────────────────────

class _VisibilitySection extends StatelessWidget {
  const _VisibilitySection({
    required this.field,
    required this.earlierFields,
    required this.onApply,
  });

  final EditorField field;
  final List<EditorField> earlierFields;
  final ValueChanged<EditorField> onApply;

  static const _operators = {
    'equals': 'Equals',
    'not_equals': 'Does not equal',
    'contains': 'Contains',
    'empty': 'Is empty',
    'not_empty': 'Is not empty',
  };

  @override
  Widget build(BuildContext context) {
    final rule = field.visibilityRule;
    final target = rule == null
        ? null
        : earlierFields
            .where((f) => f.clientId == rule.dependsOn)
            .firstOrNull;
    final needsValue =
        rule != null && rule.operator != 'empty' && rule.operator != 'not_empty';

    return CupertinoListSection.insetGrouped(
      header: const Text('Show this field only if…'),
      children: [
        CupertinoListTile(
          title: const Text('Conditional'),
          trailing: CupertinoSwitch(
            value: rule != null,
            onChanged: (v) {
              if (v) {
                onApply(field.copyWith(
                  visibilityRule: VisibilityRule(
                    dependsOn: earlierFields.first.clientId,
                    operator: 'equals',
                    value: null,
                  ),
                ));
              } else {
                onApply(field.copyWith(clearVisibilityRule: true));
              }
            },
          ),
        ),
        if (rule != null) ...[
          CupertinoListTile(
            title: const Text('Field'),
            additionalInfo: Text(
              target == null
                  ? '(removed)'
                  : (target.label.isEmpty ? '(untitled)' : target.label),
            ),
            trailing: const CupertinoListTileChevron(),
            onTap: () => _pickTarget(context, rule),
          ),
          CupertinoListTile(
            title: const Text('Condition'),
            additionalInfo: Text(_operators[rule.operator] ?? rule.operator),
            trailing: const CupertinoListTileChevron(),
            onTap: () => _pickOperator(context, rule),
          ),
          if (needsValue)
            CupertinoListTile(
              title: const Text('Value'),
              additionalInfo: Text('${rule.value ?? '(not set)'}'),
              trailing: const CupertinoListTileChevron(),
              onTap: () => _pickValue(context, rule, target),
            ),
        ],
      ],
    );
  }

  void _applyRule(VisibilityRule rule) =>
      onApply(field.copyWith(visibilityRule: rule));

  Future<void> _pickTarget(BuildContext context, VisibilityRule rule) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Depends on'),
        actions: [
          for (final f in earlierFields)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _applyRule(rule.copyWith(dependsOn: f.clientId, value: null));
              },
              child: Text(f.label.isEmpty ? '(untitled)' : f.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickOperator(BuildContext context, VisibilityRule rule) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Condition'),
        actions: [
          for (final entry in _operators.entries)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                final clearsValue =
                    entry.key == 'empty' || entry.key == 'not_empty';
                _applyRule(rule.copyWith(
                  operator: entry.key,
                  value: clearsValue ? null : rule.value,
                ));
              },
              child: Text(entry.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickValue(
      BuildContext context, VisibilityRule rule, EditorField? target) async {
    // Choice targets get an option picker; yes_no gets Yes/No; else free text.
    if (target != null && target.options.isNotEmpty) {
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: const Text('Value'),
          actions: [
            for (final o in target.options)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _applyRule(rule.copyWith(value: o.value));
                },
                child: Text(o.label),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('Cancel'),
          ),
        ),
      );
      return;
    }
    if (target != null && target.type == 'yes_no') {
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: const Text('Value'),
          actions: [
            for (final v in const ['yes', 'no'])
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _applyRule(rule.copyWith(value: v));
                },
                child: Text(v == 'yes' ? 'Yes' : 'No'),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('Cancel'),
          ),
        ),
      );
      return;
    }
    final controller = TextEditingController(text: '${rule.value ?? ''}');
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Value'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(controller: controller, autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) _applyRule(rule.copyWith(value: value));
  }
}
