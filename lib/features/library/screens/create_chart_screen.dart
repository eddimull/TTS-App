import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/library_provider.dart';

/// Full-screen modal form for creating a new chart.
///
/// Pushed via `context.push('/library/new', extra: bandId)` from
/// [LibraryScreen].  Pops with the newly created [Chart] on success so the
/// caller can navigate into the detail screen if desired.
class CreateChartScreen extends ConsumerStatefulWidget {
  const CreateChartScreen({super.key, required this.bandId});

  final int bandId;

  @override
  ConsumerState<CreateChartScreen> createState() => _CreateChartScreenState();
}

class _CreateChartScreenState extends ConsumerState<CreateChartScreen> {
  final _titleController = TextEditingController();
  final _composerController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();

  bool _isPublic = false;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _composerController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _titleController.text.trim().isNotEmpty && !_isSaving;

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final priceText = _priceController.text.trim();
    final price = priceText.isNotEmpty ? double.tryParse(priceText) : null;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final chart = await ref.read(libraryProvider.notifier).createChart(
            widget.bandId,
            title,
            composer: _composerController.text.trim().isEmpty
                ? null
                : _composerController.text.trim(),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            price: price,
            isPublic: _isPublic,
          );
      if (mounted) Navigator.of(context).pop(chart);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('New Chart'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        trailing: _isSaving
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _canSave ? _save : null,
                child: Text(
                  'Save',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    // Dim the Save label when disabled to communicate state.
                    color: _canSave
                        ? CupertinoColors.activeBlue.resolveFrom(context)
                        : CupertinoColors.tertiaryLabel.resolveFrom(context),
                  ),
                ),
              ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Cap at 700px on wide desktop/web layouts.
            final maxWidth =
                constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;

            return Center(
              child: SizedBox(
                width: maxWidth,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(top: 20, bottom: 40),
                  children: [
                    // ── Error banner ───────────────────────────────────────
                    if (_error != null)
                      _ErrorBanner(
                        message: _error!,
                        onDismiss: () => setState(() => _error = null),
                      ),

                    // ── Required fields group ──────────────────────────────
                    _FormSection(
                      children: [
                        _LabeledField(
                          label: 'Title',
                          child: CupertinoTextField(
                            controller: _titleController,
                            autofocus: true,
                            placeholder: 'Required',
                            textInputAction: TextInputAction.next,
                            decoration: const BoxDecoration(),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        _FormDivider(),
                        _LabeledField(
                          label: 'Composer',
                          child: CupertinoTextField(
                            controller: _composerController,
                            placeholder: 'Optional',
                            textInputAction: TextInputAction.next,
                            decoration: const BoxDecoration(),
                          ),
                        ),
                      ],
                    ),

                    // ── Optional details group ─────────────────────────────
                    _FormSection(
                      children: [
                        _LabeledField(
                          label: 'Description',
                          alignLabelTop: true,
                          child: CupertinoTextField(
                            controller: _descriptionController,
                            placeholder: 'Optional',
                            maxLines: 3,
                            minLines: 3,
                            textInputAction: TextInputAction.next,
                            decoration: const BoxDecoration(),
                          ),
                        ),
                        _FormDivider(),
                        _LabeledField(
                          label: 'Price',
                          child: Row(
                            children: [
                              Text(
                                '\$',
                                style: TextStyle(
                                  fontSize: 17,
                                  color: CupertinoColors.label
                                      .resolveFrom(context),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: CupertinoTextField(
                                  controller: _priceController,
                                  placeholder: '0.00',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    // Allow only digits and a single decimal point.
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d*\.?\d{0,2}')),
                                  ],
                                  textInputAction: TextInputAction.done,
                                  decoration: const BoxDecoration(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // ── Toggle group ───────────────────────────────────────
                    _FormSection(
                      children: [
                        _SwitchRow(
                          label: 'Public',
                          subtitle: 'Visible to other bands on the platform',
                          value: _isPublic,
                          onChanged: (v) => setState(() => _isPublic = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Shared form widgets ───────────────────────────────────────────────────────

/// A card-style inset group that wraps related form fields.
class _FormSection extends StatelessWidget {
  const _FormSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }
}

/// A hairline divider used between rows inside a [_FormSection].
class _FormDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 16),
      color: CupertinoColors.separator.resolveFrom(context),
    );
  }
}

/// A labelled text field row — label on the left, field fills the right.
/// When [alignLabelTop] is true the label aligns to the top of the row, which
/// suits multi-line fields like Description.
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.alignLabelTop = false,
  });

  final String label;
  final Widget child;
  final bool alignLabelTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: alignLabelTop
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Padding(
              // Small top nudge to vertically align the label with the first
              // line of text when in top-align mode.
              padding: alignLabelTop
                  ? const EdgeInsets.only(top: 4)
                  : EdgeInsets.zero,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A labelled row with a [CupertinoSwitch] on the right edge.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 16),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A dismissible red banner shown when [message] is non-null.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.systemRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CupertinoColors.systemRed.resolveFrom(context),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 16,
            color: CupertinoColors.systemRed.resolveFrom(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.systemRed.resolveFrom(context),
              ),
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: onDismiss,
            child: Icon(
              CupertinoIcons.xmark,
              size: 14,
              color: CupertinoColors.systemRed.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}
