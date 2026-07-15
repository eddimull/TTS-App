import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../logic/visibility_evaluator.dart';
import '../providers/questionnaire_editor_provider.dart';

class QuestionnairePreviewScreen extends StatefulWidget {
  const QuestionnairePreviewScreen({
    super.key,
    required this.title,
    required this.fields,
  });

  final String title;
  final List<EditorField> fields;

  @override
  State<QuestionnairePreviewScreen> createState() =>
      _QuestionnairePreviewScreenState();
}

class _QuestionnairePreviewScreenState
    extends State<QuestionnairePreviewScreen> {
  final Map<String, dynamic> _responses = {};

  List<VisibilityFieldRef> get _refs => widget.fields
      .map((f) => VisibilityFieldRef(id: f.clientId, rule: f.visibilityRule))
      .toList();

  void _set(String clientId, dynamic value) =>
      setState(() => _responses[clientId] = value);

  @override
  Widget build(BuildContext context) {
    final visible = widget.fields
        .where((f) => isFieldVisible(f.clientId, _refs, _responses))
        .toList();

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Preview')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            for (final field in visible) _buildField(field),
          ],
        ),
      ),
    );
  }

  Widget _buildField(EditorField field) {
    final label = field.label.isEmpty ? '(untitled)' : field.label;

    switch (field.type) {
      case 'header':
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(label,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        );
      case 'instructions':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(label,
              style: TextStyle(color: context.secondaryText)),
        );
      case 'yes_no':
        return _wrap(
          field,
          CupertinoSegmentedControl<String>(
            groupValue: _responses[field.clientId] as String?,
            children: const {
              'yes': Padding(padding: EdgeInsets.all(8), child: Text('Yes')),
              'no': Padding(padding: EdgeInsets.all(8), child: Text('No')),
            },
            onValueChanged: (v) => _set(field.clientId, v),
          ),
        );
      case 'dropdown':
        final selected = _responses[field.clientId] as String?;
        final selectedLabel = field.options
            .where((o) => o.value == selected)
            .firstOrNull
            ?.label;
        return _wrap(
          field,
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => _pickDropdown(field),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(selectedLabel ?? 'Select…'),
                const Icon(CupertinoIcons.chevron_down, size: 16),
              ],
            ),
          ),
        );
      case 'multi_select':
      case 'checkbox_group':
        final selected =
            (_responses[field.clientId] as List<dynamic>? ?? []).cast<String>();
        return _wrap(
          field,
          Column(
            children: [
              for (final o in field.options)
                CupertinoListTile(
                  padding: EdgeInsets.zero,
                  title: Text(o.label),
                  trailing: selected.contains(o.value)
                      ? const Icon(CupertinoIcons.check_mark_circled_solid)
                      : const Icon(CupertinoIcons.circle),
                  onTap: () {
                    final next = [...selected];
                    if (next.contains(o.value)) {
                      next.remove(o.value);
                    } else {
                      next.add(o.value);
                    }
                    _set(field.clientId, next);
                  },
                ),
            ],
          ),
        );
      case 'date':
      case 'time':
      case 'song_picker':
        return _wrap(
          field,
          Text(
            field.type == 'song_picker'
                ? 'Song picker (interactive in the client portal)'
                : '${field.type == 'date' ? 'Date' : 'Time'} picker (interactive in the client portal)',
            style: TextStyle(color: context.secondaryText),
          ),
        );
      default: // short_text, long_text, email, phone
        return _wrap(
          field,
          CupertinoTextField(
            placeholder: field.type == 'long_text' ? 'Longer answer…' : 'Answer…',
            minLines: field.type == 'long_text' ? 3 : 1,
            maxLines: field.type == 'long_text' ? 5 : 1,
            keyboardType: field.type == 'email'
                ? TextInputType.emailAddress
                : field.type == 'phone'
                    ? TextInputType.phone
                    : TextInputType.text,
            onChanged: (v) => _set(field.clientId, v),
          ),
        );
    }
  }

  Widget _wrap(EditorField field, Widget input) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  field.label.isEmpty ? '(untitled)' : field.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (field.required)
                const Text(' *',
                    style: TextStyle(color: CupertinoColors.destructiveRed)),
            ],
          ),
          if (field.helpText != null && field.helpText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(field.helpText!,
                  style:
                      TextStyle(color: context.secondaryText, fontSize: 13)),
            ),
          const SizedBox(height: 6),
          input,
        ],
      ),
    );
  }

  Future<void> _pickDropdown(EditorField field) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(field.label.isEmpty ? 'Select' : field.label),
        actions: [
          for (final o in field.options)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _set(field.clientId, o.value);
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
  }
}
