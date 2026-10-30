import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/routing_preview.dart';

/// Outcome of the Send-to sheet. A null [target] means "Don't send".
class SendToChoice {
  const SendToChoice({this.target, this.remember = false});

  final String? target;
  final bool remember;
}

/// Shows the "Send to…" modal for one answer and resolves with the user's
/// choice, or null if they cancelled.
Future<SendToChoice?> showSendToSheet(
  BuildContext context, {
  required String fieldLabel,
  required String valueDisplay,
  required List<RoutingTarget> options,
  String? currentTarget,
  bool initialRemember = false,
}) {
  return showCupertinoModalPopup<SendToChoice>(
    context: context,
    builder: (_) => SendToSheet(
      fieldLabel: fieldLabel,
      valueDisplay: valueDisplay,
      options: options,
      currentTarget: currentTarget,
      initialRemember: initialRemember,
    ),
  );
}

class SendToSheet extends StatefulWidget {
  const SendToSheet({
    super.key,
    required this.fieldLabel,
    required this.valueDisplay,
    required this.options,
    this.currentTarget,
    this.initialRemember = false,
  });

  final String fieldLabel;
  final String valueDisplay;
  final List<RoutingTarget> options;
  final String? currentTarget;

  /// Whether this answer is already marked "Remember for this questionnaire".
  final bool initialRemember;

  @override
  State<SendToSheet> createState() => _SendToSheetState();
}

class _SendToSheetState extends State<SendToSheet> {
  // Sentinel for "Don't send"; real target keys are dotted identifiers.
  static const _dontSend = '';

  late String? _selected = widget.currentTarget;
  late bool _remember = widget.initialRemember;

  RoutingTarget? get _selectedTarget =>
      widget.options.where((o) => o.key == _selected).firstOrNull;

  void _done() {
    if (_selected == null) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(SendToChoice(
      target: _selected == _dontSend ? null : _selected,
      remember: _selected != _dontSend && _remember,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final background =
        CupertinoColors.systemGroupedBackground.resolveFrom(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        // Cap the width so the sheet doesn't stretch across a desktop window.
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: SafeArea(
            top: false,
            child: DefaultTextStyle(
              style: CupertinoTheme.of(context).textTheme.textStyle,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        _answerCard(context),
                        CupertinoListSection.insetGrouped(
                          header: const Text('Where should it go?'),
                          children: [
                            for (final o in widget.options)
                              _optionTile(
                                title: o.label,
                                subtitle: o.hint,
                                selected: _selected == o.key,
                                onTap: () => setState(() => _selected = o.key),
                              ),
                            _optionTile(
                              title: "Don't send",
                              selected: _selected == _dontSend,
                              onTap: () =>
                                  setState(() => _selected = _dontSend),
                            ),
                          ],
                        ),
                        CupertinoListSection.insetGrouped(
                          children: [
                            CupertinoListTile.notched(
                              title:
                                  const Text('Remember for this questionnaire'),
                              subtitle: Text(
                                _selectedTarget == null ||
                                        _selected == _dontSend
                                    ? 'Pick a destination first'
                                    : 'Future answers to this question go to '
                                        '${_selectedTarget!.label} automatically',
                              ),
                              trailing: CupertinoSwitch(
                                value: _remember,
                                onChanged: (_selected == null ||
                                        _selected == _dontSend)
                                    ? null
                                    : (v) => setState(() => _remember = v),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          CupertinoButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const Expanded(
            child: Text(
              'Send to…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          CupertinoButton(
            onPressed: _selected == null ? null : _done,
            child: const Text('Done',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _answerCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground
            .resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.fieldLabel,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.secondaryText)),
          const SizedBox(height: 4),
          Text(widget.valueDisplay.isEmpty ? '—' : widget.valueDisplay,
              style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  Widget _optionTile({
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return CupertinoListTile.notched(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: selected
          ? Icon(CupertinoIcons.checkmark_alt,
              color: CupertinoTheme.of(context).primaryColor)
          : null,
      onTap: onTap,
    );
  }
}
