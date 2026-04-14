import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../providers/rehearsals_provider.dart';
import 'rehearsal_detail_screen.dart';

/// Resolves a virtual rehearsal key to a real [RehearsalDetail] and then
/// delegates rendering to [RehearsalDetailScreen].
class RehearsalDetailByKeyScreen extends ConsumerWidget {
  const RehearsalDetailByKeyScreen({super.key, required this.eventKey});

  final String eventKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(rehearsalDetailByKeyProvider(eventKey));

    return detailAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(),
        child: ErrorView(
          message: ErrorView.friendlyMessage(e),
          onRetry: () =>
              ref.invalidate(rehearsalDetailByKeyProvider(eventKey)),
        ),
      ),
      data: (rehearsal) => RehearsalDetailScreen(preloaded: rehearsal),
    );
  }
}
