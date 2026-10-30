import 'package:dio/dio.dart' show DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

import '../../../questionnaires/providers/routing_provider.dart';
import '../../data/models/event_detail.dart';

/// Shown right after sending questionnaire answers to this event. Lives only
/// for the app session (see [lastRoutedApplicationProvider]).
class QuestionnaireUndoBanner extends ConsumerWidget {
  const QuestionnaireUndoBanner({super.key, required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(lastRoutedApplicationProvider);
    if (app == null || !app.matches(id: event.id, key: event.key)) {
      return const SizedBox.shrink();
    }
    final green = CupertinoColors.systemGreen.resolveFrom(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          color: green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.checkmark_circle_fill, size: 18, color: green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${app.applied} answer${app.applied == 1 ? '' : 's'} sent from the questionnaire',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(44, 44),
              onPressed: () => _undo(context, ref, app),
              child: const Text('Undo'),
            ),
            CupertinoButton(
              padding: const EdgeInsets.only(right: 12),
              minimumSize: const Size(32, 44),
              onPressed: () =>
                  ref.read(lastRoutedApplicationProvider.notifier).set(null),
              child: Icon(CupertinoIcons.xmark,
                  size: 16, color: context.secondaryText),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _undo(
      BuildContext context, WidgetRef ref, RoutedApplication app) async {
    final container = ProviderScope.containerOf(context);
    String? failure;
    try {
      await undoRoutedApplication(container, app);
    } on DioException catch (e) {
      final data = e.response?.data;
      failure = data is Map && data['message'] is String
          ? data['message'] as String
          : (e.response?.statusCode == 409
              ? 'Event was edited since — undo manually.'
              : 'Please try again.');
    } catch (_) {
      failure = 'Please try again.';
    }
    if (failure == null || !context.mounted) return;
    final message = failure;
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text("Couldn't undo"),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
