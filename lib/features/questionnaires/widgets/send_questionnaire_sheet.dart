import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stub — Task 8 fills this in with the eligible-bookings + recipient picker
/// flow that calls `questionnaireInstancesProvider`'s `send`.
class SendQuestionnaireSheet extends ConsumerStatefulWidget {
  const SendQuestionnaireSheet({
    super.key,
    required this.bandId,
    required this.questionnaireId,
  });

  final int bandId;
  final int questionnaireId;

  @override
  ConsumerState<SendQuestionnaireSheet> createState() =>
      _SendQuestionnaireSheetState();
}

class _SendQuestionnaireSheetState
    extends ConsumerState<SendQuestionnaireSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );
  }
}
