import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stub — Task 9 fills this in with the read-only rendering of a sent
/// instance's responses, driven by `instanceDetailProvider`.
class InstanceResponsesScreen extends ConsumerWidget {
  const InstanceResponsesScreen({
    super.key,
    required this.questionnaireId,
    required this.instanceId,
  });

  final int questionnaireId;
  final int instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('Response')),
      child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
    );
  }
}
