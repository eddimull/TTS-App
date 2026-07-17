import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../features/auth/data/models/band_summary.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/questionnaire_field.dart';
import '../data/models/questionnaire_instance.dart';
import '../logic/visibility_evaluator.dart';
import '../providers/questionnaire_instances_provider.dart';
import '../widgets/instance_status_badge.dart';

class InstanceResponsesScreen extends ConsumerWidget {
  const InstanceResponsesScreen({
    super.key,
    required this.questionnaireId,
    required this.instanceId,
  });

  final int questionnaireId;
  final int instanceId;

  String _fmt(DateTime? d) =>
      d == null ? '—' : DateFormat('MMM d, yyyy h:mm a').format(d.toLocal());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider).value;
    final bandId = ref.watch(selectedBandProvider).value;
    final bands = authState is AuthAuthenticated
        ? authState.bands
        : const <BandSummary>[];
    final currentBand =
        bandId == null ? null : bands.where((b) => b.id == bandId).firstOrNull;
    final isOwner = currentBand?.isOwner ?? false;

    const navBarTitle = Text('Responses');

    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: navBarTitle),
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    final key = (bandId: bandId, instanceId: instanceId);
    final detailAsync = ref.watch(instanceDetailProvider(key));

    if (detailAsync.isLoading && !detailAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: navBarTitle),
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }
    if (detailAsync.hasError && !detailAsync.hasValue) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: navBarTitle),
        child: SafeArea(
          child: Center(
            child: Text('Failed to load responses.',
                style: TextStyle(color: context.secondaryText)),
          ),
        ),
      );
    }

    final instance = detailAsync.value!;
    final refs = instance.fields
        .map((f) => VisibilityFieldRef(id: '${f.id}', rule: f.visibilityRule))
        .toList();
    final visibleFields = instance.fields
        .where((f) => isFieldVisible('${f.id}', refs, instance.responses))
        .toList();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: navBarTitle,
        trailing: isOwner
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showActions(context, ref, bandId, instance),
                child: const Icon(CupertinoIcons.ellipsis_circle, size: 22),
              )
            : null,
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            CupertinoSliverRefreshControl(
              onRefresh: () async => ref.invalidate(instanceDetailProvider(key)),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            instance.name,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                        ),
                        InstanceStatusBadge(status: instance.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${instance.bookingName} · ${instance.recipientName}',
                      style: TextStyle(color: context.secondaryText),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sent ${_fmt(instance.sentAt)}'
                      '${instance.firstOpenedAt != null ? ' · opened ${_fmt(instance.firstOpenedAt)}' : ''}'
                      '${instance.submittedAt != null ? ' · submitted ${_fmt(instance.submittedAt)}' : ''}',
                      style: TextStyle(
                          color: context.secondaryText, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  for (final field in visibleFields)
                    _FieldAnswer(field: field, instance: instance),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref, int bandId,
      QuestionnaireInstance instance) async {
    final qId = instance.questionnaireId ?? questionnaireId;
    final listKey = (bandId: bandId, questionnaireId: qId);
    final detailKey = (bandId: bandId, instanceId: instanceId);
    final notifier =
        ref.read(questionnaireInstancesProvider(listKey).notifier);

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              try {
                await notifier.resend(instance.id);
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
                ref.invalidate(instanceDetailProvider(detailKey));
              } catch (_) {
                if (context.mounted) {
                  _info(context,
                      instance.isLocked ? 'Unlock failed' : 'Lock failed',
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
              try {
                await notifier.deleteInstance(instance.id);
                if (context.mounted) Navigator.of(context).pop();
              } catch (_) {
                if (context.mounted) {
                  _info(context, 'Delete failed', 'Please try again.');
                }
              }
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

class _FieldAnswer extends StatelessWidget {
  const _FieldAnswer({required this.field, required this.instance});

  final QuestionnaireField field;
  final QuestionnaireInstance instance;

  @override
  Widget build(BuildContext context) {
    if (field.type == 'header') {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(field.label,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      );
    }
    if (field.type == 'instructions') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(field.label,
            style: TextStyle(color: context.secondaryText, fontSize: 13)),
      );
    }

    final raw = instance.responses['${field.id}'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label,
              style: TextStyle(
                  color: context.secondaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          _answer(context, raw),
        ],
      ),
    );
  }

  Widget _answer(BuildContext context, dynamic raw) {
    if (raw == null || (raw is String && raw.isEmpty) || (raw is List && raw.isEmpty)) {
      return Text('—', style: TextStyle(color: context.secondaryText));
    }

    if (field.type == 'song_picker' && raw is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final id in raw)
            Text(instance.songLookup['$id']?.display ?? '(removed song #$id)'),
        ],
      );
    }

    if (raw is List) {
      // multi_select / checkbox_group: map option values back to labels.
      final labels = raw.map((v) {
        final match =
            field.options.where((o) => o.value == '$v').firstOrNull;
        return match?.label ?? '$v';
      });
      return Text(labels.join(', '));
    }

    if (field.type == 'yes_no') {
      return Text('$raw' == 'yes' ? 'Yes' : ('$raw' == 'no' ? 'No' : '$raw'));
    }

    if (field.type == 'dropdown') {
      final match =
          field.options.where((o) => o.value == '$raw').firstOrNull;
      return Text(match?.label ?? '$raw');
    }

    return Text('$raw');
  }
}
