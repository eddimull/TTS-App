import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../features/auth/data/models/band_summary.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/questionnaire.dart';
import '../data/models/questionnaire_instance.dart';
import '../providers/questionnaire_editor_provider.dart';
import '../providers/questionnaire_instances_provider.dart';
import '../providers/questionnaires_provider.dart';
import '../widgets/instance_status_badge.dart';
import '../widgets/send_questionnaire_sheet.dart';
import 'questionnaire_preview_screen.dart';

class QuestionnaireDetailScreen extends ConsumerStatefulWidget {
  const QuestionnaireDetailScreen({super.key, required this.questionnaireId});

  final int questionnaireId;

  @override
  ConsumerState<QuestionnaireDetailScreen> createState() =>
      _QuestionnaireDetailScreenState();
}

class _QuestionnaireDetailScreenState
    extends ConsumerState<QuestionnaireDetailScreen> {
  String? _statusFilter; // null = all

  static const _filters = [
    (null, 'All'),
    ('sent', 'Sent'),
    ('in_progress', 'In progress'),
    ('submitted', 'Submitted'),
    ('locked', 'Locked'),
  ];

  @override
  Widget build(BuildContext context) {
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
        navigationBar: CupertinoNavigationBar(middle: Text('Questionnaire')),
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    final detailKey = (bandId: bandId, questionnaireId: widget.questionnaireId);
    final detailAsync = ref.watch(questionnaireDetailProvider(detailKey));
    final instancesAsync =
        ref.watch(questionnaireInstancesProvider(detailKey));

    final title = detailAsync.value?.name ?? 'Questionnaire';

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(title, overflow: TextOverflow.ellipsis),
        trailing: isOwner
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showSendSheet(bandId),
                child: const Text('Send'),
              )
            : null,
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            CupertinoSliverRefreshControl(
              onRefresh: () async {
                ref.invalidate(questionnaireDetailProvider(detailKey));
                await ref
                    .read(questionnaireInstancesProvider(detailKey).notifier)
                    .refresh();
              },
            ),
            SliverToBoxAdapter(child: _summarySection(detailAsync, isOwner)),
            SliverToBoxAdapter(child: _filterRow()),
            _instancesSliver(instancesAsync, detailKey, isOwner),
          ],
        ),
      ),
    );
  }

  Widget _summarySection(AsyncValue<Questionnaire> detailAsync, bool isOwner) {
    final q = detailAsync.value;
    if (q == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (q.description != null && q.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(q.description!,
                  style: TextStyle(color: context.secondaryText)),
            ),
          Row(
            children: [
              Text(
                q.instancesCount == 0
                    ? 'Never sent'
                    : 'Sent ${q.instancesCount} time${q.instancesCount == 1 ? '' : 's'}',
                style: TextStyle(color: context.secondaryText, fontSize: 13),
              ),
              const Spacer(),
              if (isOwner)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      context.push('/questionnaires/${widget.questionnaireId}/edit'),
                  child: const Text('Edit'),
                ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _openPreview(q),
                child: const Text('Preview'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final (value, label) in _filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _statusFilter = value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _statusFilter == value
                        ? CupertinoColors.systemBlue.resolveFrom(context)
                        : CupertinoColors.tertiarySystemBackground
                            .resolveFrom(context),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _statusFilter == value
                          ? CupertinoColors.white
                          : CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _instancesSliver(
    AsyncValue<List<QuestionnaireInstance>> instancesAsync,
    ({int bandId, int questionnaireId}) detailKey,
    bool isOwner,
  ) {
    if (instancesAsync.isLoading && !instancesAsync.hasValue) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }
    if (instancesAsync.hasError && !instancesAsync.hasValue) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text('Failed to load sent questionnaires.',
                style: TextStyle(color: context.secondaryText)),
          ),
        ),
      );
    }
    final all = instancesAsync.value!;
    final filtered = _statusFilter == null
        ? all
        : all.where((i) => i.status == _statusFilter).toList();

    if (filtered.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              all.isEmpty
                  ? 'Not sent to anyone yet.'
                  : 'No sent questionnaires match this filter.',
              style: TextStyle(color: context.secondaryText),
            ),
          ),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: CupertinoListSection.insetGrouped(
        header: const Text('Sent'),
        children: [
          for (final i in filtered)
            _InstanceRow(
              instance: i,
              detailKey: detailKey,
              isOwner: isOwner,
              questionnaireId: widget.questionnaireId,
            ),
        ],
      ),
    );
  }

  Future<void> _showSendSheet(int bandId) async {
    final container = ProviderScope.containerOf(context);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: SendQuestionnaireSheet(
          bandId: bandId,
          questionnaireId: widget.questionnaireId,
        ),
      ),
    );
  }

  void _openPreview(Questionnaire q) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => QuestionnairePreviewScreen(
          title: q.name,
          fields: editorFieldsFromQuestionnaire(q),
        ),
      ),
    );
  }
}

class _InstanceRow extends ConsumerWidget {
  const _InstanceRow({
    required this.instance,
    required this.detailKey,
    required this.isOwner,
    required this.questionnaireId,
  });

  final QuestionnaireInstance instance;
  final ({int bandId, int questionnaireId}) detailKey;
  final bool isOwner;
  final int questionnaireId;

  String _fmt(DateTime? d) =>
      d == null ? '—' : DateFormat('MMM d, yyyy').format(d.toLocal());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = instance;
    return GestureDetector(
      onLongPress: isOwner ? () => _showActions(context, ref) : null,
      child: CupertinoListTile(
        title: Row(
          children: [
            Expanded(
              child:
                  Text(i.bookingName, overflow: TextOverflow.ellipsis),
            ),
            InstanceStatusBadge(status: i.status),
          ],
        ),
        subtitle: Text(
          '${i.recipientName} · sent ${_fmt(i.sentAt)}'
          '${i.submittedAt != null ? ' · submitted ${_fmt(i.submittedAt)}' : ''}',
        ),
        trailing: const CupertinoListTileChevron(),
        onTap: () => context
            .push('/questionnaires/$questionnaireId/instances/${i.id}'),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final notifier =
        ref.read(questionnaireInstancesProvider(detailKey).notifier);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text('${instance.name} — ${instance.recipientName}'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              try {
                await notifier.resend(instance.id);
                if (context.mounted) {
                  _info(context, 'Sent', 'The questionnaire email was re-sent.');
                }
              } catch (_) {
                if (context.mounted) {
                  _info(context, 'Resend failed', 'Please try again.');
                }
              }
            },
            child: const Text('Resend email'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              try {
                if (instance.isLocked) {
                  await notifier.unlock(instance.id);
                } else {
                  await notifier.lock(instance.id);
                }
              } catch (_) {
                if (context.mounted) {
                  _info(context, instance.isLocked ? 'Unlock failed' : 'Lock failed',
                      'Please try again.');
                }
              }
            },
            child: Text(instance.isLocked ? 'Unlock' : 'Lock'),
          ),
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
        title: const Text('Delete sent questionnaire?'),
        content: Text(
            'The copy sent to ${instance.recipientName} and any answers will be removed.'),
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
          .read(questionnaireInstancesProvider(detailKey).notifier)
          .deleteInstance(instance.id);
    } catch (_) {
      if (context.mounted) {
        _info(context, 'Delete failed', 'Please try again.');
      }
    }
  }

  void _info(BuildContext context, String title, String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
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
