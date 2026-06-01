import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/setlist_prompt_template.dart';
import '../providers/prompt_templates_provider.dart';

// ── Public API ────────────────────────────────────────────────────────────────

/// The value returned when the user taps "Generate".
///
/// [context] is null when the textarea was left blank (caller should still
/// proceed — the backend treats a missing context as "no extra instructions").
class GenerateRequest {
  const GenerateRequest(this.context);
  final String? context;
}

/// Shows the AI Generate bottom sheet.
///
/// Returns a [GenerateRequest] if the user taps Generate, or null if they
/// cancel. The caller is responsible for invoking
/// `setlistEditorProvider(eventKey).notifier.generate(context: result.context)`
/// after this future completes with a non-null value.
///
/// [bandId] is used to load and save prompt templates via
/// [promptTemplatesProvider].
Future<GenerateRequest?> showGenerateSheet(
  BuildContext context, {
  required int bandId,
}) {
  // Capture the container before entering the new route so that
  // showCupertinoModalPopup's independent BuildContext can re-attach to the
  // same ProviderScope. This is the house pattern (matches chart_detail_screen).
  final container = ProviderScope.containerOf(context);
  return showCupertinoModalPopup<GenerateRequest>(
    context: context,
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: _GenerateSheet(bandId: bandId),
    ),
  );
}

// ── Private widget ────────────────────────────────────────────────────────────

class _GenerateSheet extends ConsumerStatefulWidget {
  const _GenerateSheet({required this.bandId});
  final int bandId;

  @override
  ConsumerState<_GenerateSheet> createState() => _GenerateSheetState();
}

class _GenerateSheetState extends ConsumerState<_GenerateSheet> {
  final _contextCtrl = TextEditingController();
  final _newTplNameCtrl = TextEditingController();

  /// Non-null when a template has been tapped and loaded into the textarea.
  SetlistPromptTemplate? _loadedTpl;

  @override
  void dispose() {
    _contextCtrl.dispose();
    _newTplNameCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(promptTemplatesProvider(widget.bandId));

    return Container(
      // 75 % of screen height; keyboard avoidance via viewInsets.
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _grabber(),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Generate Setlist',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            // Scrollable body: templates strip + context field + save-prompt row.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Templates strip — handled for all three async states.
                    templatesAsync.when(
                      data: (list) => list.isEmpty
                          ? const SizedBox.shrink()
                          : _TemplatesStrip(
                              templates: list,
                              selectedId: _loadedTpl?.id,
                              onSelected: _loadTemplate,
                            ),
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: CupertinoActivityIndicator()),
                      ),
                      // On error just hide the strip — context field still usable.
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Additional context (optional)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        // Resolve dynamic color — do NOT freeze in const.
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    CupertinoTextField(
                      controller: _contextCtrl,
                      placeholder:
                          'e.g. Keep energy high. End with something slow.',
                      maxLines: 5,
                      padding: const EdgeInsets.all(12),
                      onChanged: (_) => setState(() {}),
                    ),
                    // "Loaded from template" indicator.
                    if (_loadedTpl != null) _loadedLabel(context),
                    const SizedBox(height: 16),
                    // Save-as-prompt row — only shown when there is unsaved text
                    // that did not come from an existing template.
                    if (_contextCtrl.text.trim().isNotEmpty &&
                        _loadedTpl == null)
                      _SavePromptRow(
                        nameCtrl: _newTplNameCtrl,
                        onSave: _saveAsTemplate,
                      ),
                  ],
                ),
              ),
            ),
            // Fixed footer: Cancel + Generate buttons.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: () => Navigator.pop(
                        context,
                        GenerateRequest(
                          _contextCtrl.text.trim().isEmpty
                              ? null
                              : _contextCtrl.text.trim(),
                        ),
                      ),
                      child: const Text('Generate'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _grabber() => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey3.resolveFrom(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _loadedLabel(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.bookmark,
            size: 12,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
          const SizedBox(width: 4),
          Text(
            'Loaded: ${_loadedTpl!.name}',
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          const Spacer(),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => setState(() => _loadedTpl = null),
            child: const Text(
              'Clear',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _loadTemplate(SetlistPromptTemplate tpl) {
    setState(() {
      _loadedTpl = tpl;
      _contextCtrl.text = tpl.prompt;
    });
  }

  Future<void> _saveAsTemplate() async {
    final name = _newTplNameCtrl.text.trim();
    final prompt = _contextCtrl.text.trim();
    if (name.isEmpty || prompt.isEmpty) return;

    try {
      final created = await ref
          .read(promptTemplatesProvider(widget.bandId).notifier)
          .create(name: name, prompt: prompt);
      _newTplNameCtrl.clear();
      // Mark as loaded so the save row hides and the loaded label appears.
      setState(() => _loadedTpl = created);
    } catch (_) {
      // Surfaced via provider error state; non-blocking for the generate flow.
    }
  }
}

// ── Sub-widgets (private) ─────────────────────────────────────────────────────

/// Horizontal wrapping strip of prompt template chip buttons.
///
/// Extracted as a [StatelessWidget] so that the parent's [setState] calls
/// triggered by template selection do not rebuild the entire sheet.
class _TemplatesStrip extends StatelessWidget {
  const _TemplatesStrip({
    required this.templates,
    required this.selectedId,
    required this.onSelected,
  });

  final List<SetlistPromptTemplate> templates;
  final int? selectedId;
  final ValueChanged<SetlistPromptTemplate> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Saved prompts — tap to load',
          style: TextStyle(
            fontSize: 12,
            // Resolve dynamic color at build time; never const in TextStyle.
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: templates.map((tpl) {
            final isSelected = selectedId == tpl.id;
            return CupertinoButton(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              // withValues(alpha:) — Flutter 3.41 idiom; withOpacity is
              // deprecated and emits a lint warning.
              color: isSelected
                  ? CupertinoColors.activeBlue
                  : CupertinoColors.systemGrey5
                      .resolveFrom(context)
                      .withValues(alpha: 1.0),
              borderRadius: BorderRadius.circular(20),
              onPressed: () => onSelected(tpl),
              child: Text(
                tpl.name,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected
                      ? CupertinoColors.white
                      : CupertinoColors.label.resolveFrom(context),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Name field + "Save" button shown when there is unsaved context text.
class _SavePromptRow extends StatelessWidget {
  const _SavePromptRow({
    required this.nameCtrl,
    required this.onSave,
  });

  final TextEditingController nameCtrl;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CupertinoTextField(
            controller: nameCtrl,
            placeholder: 'Save prompt as…',
            padding: const EdgeInsets.all(10),
          ),
        ),
        const SizedBox(width: 8),
        // ListenableBuilder keeps this button reactive to nameCtrl changes
        // without rebuilding the whole sheet.
        ListenableBuilder(
          listenable: nameCtrl,
          builder: (context, _) => CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: Size.zero,
            onPressed: nameCtrl.text.trim().isEmpty ? null : onSave,
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}
