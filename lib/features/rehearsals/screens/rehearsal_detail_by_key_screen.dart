import 'package:flutter/material.dart';
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
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          message: 'Could not load rehearsal.\n$e',
          onRetry: () =>
              ref.invalidate(rehearsalDetailByKeyProvider(eventKey)),
        ),
      ),
      data: (rehearsal) => RehearsalDetailScreen(preloaded: rehearsal),
    );
  }
}
