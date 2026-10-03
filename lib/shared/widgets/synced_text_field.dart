import 'package:flutter/cupertino.dart';

/// A [CupertinoTextField] driven by an external string [value] (typically a
/// Riverpod state field) that keeps the caret where the user left it.
///
/// Building a `TextEditingController(text: value)` inline on every rebuild
/// resets the selection — usually to the end of the text — so typing in the
/// middle of a field whose `onChanged` feeds back into widget state throws the
/// cursor around on every keystroke. This widget owns one controller for its
/// lifetime and only pushes [value] into it when it differs from what the
/// field already shows (i.e. a genuine external change, not the echo of the
/// user's own edit), clamping the existing selection into the new text.
class SyncedTextField extends StatefulWidget {
  const SyncedTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.style,
    this.maxLines = 1,
    this.minLines,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final TextStyle? style;
  final int? maxLines;
  final int? minLines;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value || widget.value == _controller.text) {
      return;
    }
    final length = widget.value.length;
    final old = _controller.selection;
    final selection = old.isValid
        ? TextSelection(
            baseOffset: old.baseOffset.clamp(0, length),
            extentOffset: old.extentOffset.clamp(0, length),
          )
        : TextSelection.collapsed(offset: length);
    _controller.value = TextEditingValue(
      text: widget.value,
      selection: selection,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: _controller,
      onChanged: widget.onChanged,
      placeholder: widget.placeholder,
      style: widget.style,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
    );
  }
}
