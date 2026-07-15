import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuestionnaireEditorScreen extends ConsumerStatefulWidget {
  const QuestionnaireEditorScreen({super.key, required this.questionnaireId});

  final int questionnaireId;

  @override
  ConsumerState<QuestionnaireEditorScreen> createState() =>
      _QuestionnaireEditorScreenState();
}

class _QuestionnaireEditorScreenState
    extends ConsumerState<QuestionnaireEditorScreen> {
  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('Edit Questionnaire')),
      child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
    );
  }
}
