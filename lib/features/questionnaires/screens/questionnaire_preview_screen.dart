import 'package:flutter/cupertino.dart';
import '../providers/questionnaire_editor_provider.dart';

/// Stub for Task 12. Replaced with the real read-only preview (renders
/// [fields] as a filled-out form) in that task.
class QuestionnairePreviewScreen extends StatelessWidget {
  const QuestionnairePreviewScreen({
    super.key,
    required this.title,
    required this.fields,
  });

  final String title;
  final List<EditorField> fields;

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('Preview')),
      child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
    );
  }
}
