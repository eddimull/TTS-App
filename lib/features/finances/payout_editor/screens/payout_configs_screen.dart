import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../data/payout_flow_repository.dart';
import '../providers/payout_flow_provider.dart';

/// Lists a band's payout configs; tapping one opens an action sheet (owners) or
/// the read-only editor (non-owners). Owners can create a config from a template.
class PayoutConfigsScreen extends ConsumerWidget {
  const PayoutConfigsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandAsync = ref.watch(selectedBandProvider);
    final isOwner = ref.watch(isSelectedBandOwnerProvider);

    return bandAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Payout Flow')),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Payout Flow')),
        child: ErrorView(message: ErrorView.friendlyMessage(e)),
      ),
      data: (bandId) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: const Text('Payout Flow'),
          trailing: (bandId != null && isOwner)
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => _startCreate(context, ref, bandId),
                  child: const Icon(CupertinoIcons.add, semanticLabel: 'New payout config'),
                )
              : null,
        ),
        child: bandId == null
            ? const ErrorView(message: 'No band selected.')
            : _ConfigsList(bandId: bandId),
      ),
    );
  }

  /// Create flow: pick a template, name it, create, open the editor.
  Future<void> _startCreate(BuildContext context, WidgetRef ref, int bandId) async {
    final templates =
        await ref.read(payoutFlowRepositoryProvider).listTemplates(bandId);
    if (!context.mounted || templates.isEmpty) return;

    final template = await showCupertinoModalPopup<PayoutTemplate>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        title: const Text('Start from a template'),
        actions: [
          for (final tpl in templates)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetCtx, tpl),
              child: Column(
                children: [
                  Text(tpl.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(tpl.description,
                      style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.systemGrey.resolveFrom(sheetCtx))),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetCtx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (template == null || !context.mounted) return;

    final name = await _promptName(context, template.name);
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    try {
      final detail = await ref
          .read(payoutConfigsProvider(bandId).notifier)
          .createConfig(name.trim(), template.key);
      if (!context.mounted) return;
      context.push('/finances/payout-flow/$bandId/${detail.id}');
    } catch (e) {
      if (context.mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (dlg) => CupertinoAlertDialog(
            title: const Text('Could not create'),
            content: Text(ErrorView.friendlyMessage(e)),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dlg),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<String?> _promptName(BuildContext context, String initial) {
    final controller = TextEditingController(text: initial);
    return showCupertinoDialog<String>(
      context: context,
      builder: (dlg) => CupertinoAlertDialog(
        title: const Text('Name this config'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(controller: controller, autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dlg, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}

class _ConfigsList extends ConsumerWidget {
  const _ConfigsList({required this.bandId});
  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(payoutConfigsProvider(bandId));
    final isOwner = ref.watch(isSelectedBandOwnerProvider);

    return configsAsync.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => ErrorView(
        message: ErrorView.friendlyMessage(e),
        onRetry: () => ref.read(payoutConfigsProvider(bandId).notifier).refresh(),
      ),
      data: (configs) {
        if (configs.isEmpty) {
          return EmptyStateView(
            icon: CupertinoIcons.money_dollar_circle,
            title: 'No payout configs',
            // Only owners see the + button, so only they get the create hint.
            subtitle: isOwner
                ? 'Tap + to create one from a template.'
                : 'Payout flow configurations for this band will appear here.',
          );
        }
        return CupertinoScrollbar(
          child: ListView.separated(
            itemCount: configs.length,
            separatorBuilder: (_, __) => Container(
              height: 0.5,
              margin: const EdgeInsets.only(left: 16),
              color: CupertinoColors.separator,
            ),
            itemBuilder: (context, i) {
              final c = configs[i];
              return CupertinoListTile(
                title: Text(c.name),
                subtitle: isOwner ? null : const Text('View only'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.isActive) const _ActiveBadge(),
                    const SizedBox(width: 6),
                    const CupertinoListTileChevron(),
                  ],
                ),
                onTap: () => isOwner
                    ? _showRowActions(context, ref, bandId, c)
                    : context.push('/finances/payout-flow/$bandId/${c.id}'),
              );
            },
          ),
        );
      },
    );
  }

  /// Owner row tap: choose Open editor / Set as active.
  void _showRowActions(
      BuildContext context, WidgetRef ref, int bandId, PayoutConfigSummary c) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        title: Text(c.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetCtx);
              context.push('/finances/payout-flow/$bandId/${c.id}');
            },
            child: const Text('Open editor'),
          ),
          if (!c.isActive)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(sheetCtx);
                try {
                  await ref
                      .read(payoutConfigsProvider(bandId).notifier)
                      .setActive(c.id);
                } catch (e) {
                  if (context.mounted) {
                    await showCupertinoDialog<void>(
                      context: context,
                      builder: (dlg) => CupertinoAlertDialog(
                        title: const Text('Could not set active'),
                        content: Text(ErrorView.friendlyMessage(e)),
                        actions: [
                          CupertinoDialogAction(
                            onPressed: () => Navigator.pop(dlg),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  }
                }
              },
              child: const Text('Set as active'),
            ),
          // Deleting the active config is blocked here (frontend-only): the
          // Delete action is only offered for inactive configs. Activate another
          // first to remove this one.
          if (!c.isActive)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(sheetCtx);
                _confirmDelete(context, ref, bandId, c);
              },
              child: const Text('Delete'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetCtx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  /// Confirm + delete a config, then the notifier refreshes the list.
  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, int bandId, PayoutConfigSummary c) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dlg) => CupertinoAlertDialog(
        title: const Text('Delete config?'),
        content: Text('"${c.name}" will be permanently deleted.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dlg, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dlg, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(payoutConfigsProvider(bandId).notifier).deleteConfig(c.id);
    } catch (e) {
      if (context.mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (dlg) => CupertinoAlertDialog(
            title: const Text('Could not delete'),
            content: Text(ErrorView.friendlyMessage(e)),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dlg),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge();
  @override
  Widget build(BuildContext context) {
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('Active',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: green)),
    );
  }
}
