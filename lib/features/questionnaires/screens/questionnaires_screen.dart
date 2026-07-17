import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../features/auth/data/models/band_summary.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/questionnaire.dart';
import '../providers/questionnaire_editor_provider.dart';
import '../providers/questionnaires_provider.dart';
import '../widgets/create_questionnaire_sheet.dart';
import 'questionnaire_preview_screen.dart';

class QuestionnairesScreen extends ConsumerWidget {
  const QuestionnairesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const navBar = CupertinoNavigationBar(middle: Text('Questionnaires'));
    final authState = ref.watch(authProvider).value;
    final bandId = ref.watch(selectedBandProvider).value;
    final bands = authState is AuthAuthenticated
        ? authState.bands
        : const <BandSummary>[];
    final currentBand =
        bandId == null ? null : bands.where((b) => b.id == bandId).firstOrNull;
    final isOwner = currentBand?.isOwner ?? false;

    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    final listAsync = ref.watch(questionnairesProvider(bandId));

    if (listAsync.isLoading && !listAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    if (listAsync.hasError && !listAsync.hasValue) {
      return CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(
          child: Center(
            child: Text(
              'Failed to load questionnaires.',
              style: TextStyle(color: context.secondaryText),
            ),
          ),
        ),
      );
    }

    final all = listAsync.value!;
    final active = all.where((q) => !q.isArchived).toList();
    final archived = all.where((q) => q.isArchived).toList();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Questionnaires'),
        trailing: isOwner
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showCreateSheet(context, bandId),
                child: const Icon(CupertinoIcons.add),
              )
            : null,
      ),
      child: SafeArea(
        child: all.isEmpty
            ? Center(
                child: Text(
                  isOwner
                      ? 'No questionnaires yet. Tap + to create one.'
                      : 'No questionnaires yet.',
                  style: TextStyle(color: context.secondaryText),
                ),
              )
            : ListView(
                children: [
                  if (active.isNotEmpty)
                    CupertinoListSection.insetGrouped(
                      children: [
                        for (final q in active)
                          _QuestionnaireRow(
                              questionnaire: q, bandId: bandId, isOwner: isOwner),
                      ],
                    ),
                  if (archived.isNotEmpty)
                    CupertinoListSection.insetGrouped(
                      header: const Text('Archived'),
                      children: [
                        for (final q in archived)
                          _QuestionnaireRow(
                              questionnaire: q, bandId: bandId, isOwner: isOwner),
                      ],
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _showCreateSheet(BuildContext context, int bandId) async {
    // Capture the container before entering the new route so that
    // showCupertinoModalPopup's independent BuildContext can re-attach to the
    // same ProviderScope. This is the house pattern (matches generate_sheet).
    final container = ProviderScope.containerOf(context);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: CreateQuestionnaireSheet(bandId: bandId),
      ),
    );
  }
}

class _QuestionnaireRow extends ConsumerWidget {
  const _QuestionnaireRow({
    required this.questionnaire,
    required this.bandId,
    required this.isOwner,
  });

  final Questionnaire questionnaire;
  final int bandId;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = questionnaire;
    return GestureDetector(
      onLongPress: () => _showActions(context, ref),
      child: CupertinoListTile(
        title: Text(q.name),
        subtitle: Text(
          q.instancesCount == 0
              ? 'Never sent'
              : 'Sent ${q.instancesCount} time${q.instancesCount == 1 ? '' : 's'}',
        ),
        trailing: const CupertinoListTileChevron(),
        onTap: () => context.push('/questionnaires/${q.id}'),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final q = questionnaire;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(q.name),
        actions: [
          if (isOwner)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                context.push('/questionnaires/${q.id}/edit');
              },
              child: const Text('Edit'),
            ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              final detail = await ref.read(questionnaireDetailProvider(
                  (bandId: bandId, questionnaireId: q.id)).future);
              if (!context.mounted) return;
              Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => QuestionnairePreviewScreen(
                    title: detail.name,
                    fields: editorFieldsFromQuestionnaire(detail),
                  ),
                ),
              );
            },
            child: const Text('Preview'),
          ),
          if (isOwner && !q.isArchived)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                try {
                  await ref
                      .read(questionnairesProvider(bandId).notifier)
                      .archive(q.id);
                } catch (_) {
                  if (!context.mounted) return;
                  await showCupertinoDialog<void>(
                    context: context,
                    builder: (dialogContext) => CupertinoAlertDialog(
                      title: const Text('Archive failed'),
                      content: const Text('Please try again.'),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              },
              child: const Text('Archive'),
            ),
          if (isOwner && q.isArchived)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                try {
                  await ref
                      .read(questionnairesProvider(bandId).notifier)
                      .restoreArchived(q.id);
                } catch (_) {
                  if (!context.mounted) return;
                  await showCupertinoDialog<void>(
                    context: context,
                    builder: (dialogContext) => CupertinoAlertDialog(
                      title: const Text('Restore failed'),
                      content: const Text('Please try again.'),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              },
              child: const Text('Restore'),
            ),
          if (isOwner)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                await _confirmDelete(context, ref);
              },
              child: const Text('Delete'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Delete questionnaire?'),
        content: Text('"${questionnaire.name}" will be permanently removed.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(questionnairesProvider(bandId).notifier)
          .delete(questionnaire.id);
    } on DioException catch (e) {
      if (!context.mounted) return;
      if (e.response?.statusCode == 409) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Cannot delete'),
            content: const Text(
                'This questionnaire has been sent and can\'t be deleted — archive it instead.'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        await showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Delete failed'),
            content: const Text(
                'Could not delete the questionnaire. Please try again.'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Delete failed'),
          content: const Text(
              'Could not delete the questionnaire. Please try again.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}
