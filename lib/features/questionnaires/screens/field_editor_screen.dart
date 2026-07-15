import 'package:flutter/cupertino.dart';

/// Stub for Task 11. Replaced with the real field editor (label, type,
/// options, visibility rule, mapping target) in that task.
class FieldEditorScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('Edit Field')),
      child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
    );
  }
}
