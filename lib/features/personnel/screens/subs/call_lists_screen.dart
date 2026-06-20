import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../contacts/contact_detail_screen.dart';
import '../../../contacts/contact_ref.dart';
import '../../data/models/call_list_entry.dart';
import '../../providers/subs_provider.dart';
import 'add_call_list_entry_sheet.dart';

/// Per-role substitute call lists, grouped by instrument and shown in priority
/// order. Adding a custom person here invites them to sub for the band.
class CallListsScreen extends ConsumerWidget {
  const CallListsScreen({super.key, required this.bandId});

  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(callListsProvider(bandId));

    final navBar = CupertinoNavigationBar(
      middle: const Text('Call Lists'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => _add(context),
        child: const Icon(CupertinoIcons.add),
      ),
    );

    return CupertinoPageScaffold(
      navigationBar: navBar,
      child: SafeArea(
        child: async.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (_, __) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Failed to load call lists.',
                  style: TextStyle(color: CupertinoColors.secondaryLabel),
                ),
                const SizedBox(height: 12),
                CupertinoButton(
                  onPressed: () =>
                      ref.read(callListsProvider(bandId).notifier).refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (groups) {
            if (groups.isEmpty) {
              return _EmptyHint(onAdd: () => _add(context));
            }
            return ListView(
              children: [
                const SizedBox(height: 16),
                for (final group in groups)
                  CupertinoListSection.insetGrouped(
                    header: Text(group.instrument.toUpperCase()),
                    children: [
                      for (var i = 0; i < group.entries.length; i++)
                        _EntryRow(
                          bandId: bandId,
                          entry: group.entries[i],
                          order: i + 1,
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => AddCallListEntrySheet(bandId: bandId),
    );
  }
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({
    required this.bandId,
    required this.entry,
    required this.order,
  });

  final int bandId;
  final CallListEntry entry;
  final int order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = CupertinoListTile(
      leading: _PriorityBadge(order: order),
      title: Text(entry.name ?? entry.email ?? 'Sub'),
      subtitle: entry.isCustom ? const Text('Custom') : null,
      trailing: const CupertinoListTileChevron(),
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => ContactDetailScreen(
            contact: ContactRef(
              name: entry.name ?? entry.email ?? 'Sub',
              email: entry.email,
              phone: entry.phone,
              role: entry.instrument,
              isSub: true,
            ),
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('calllist-${entry.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmRemove(context, ref),
      background: Container(
        color: CupertinoColors.destructiveRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
      ),
      child: tile,
    );
  }

  Future<bool?> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Remove from Call List'),
        content: Text('Remove ${entry.name ?? entry.email} from this list?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return false;

    try {
      await ref.read(callListsProvider(bandId).notifier).deleteEntry(entry.id);
    } catch (_) {
      if (context.mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to remove. Please try again.'),
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
    return false;
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.order});

  final int order;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey5.resolveFrom(context),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$order',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Text(
            'No call lists yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add backups by role so you know who to call first.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 16),
          CupertinoButton.filled(
            onPressed: onAdd,
            child: const Text('Add to Call List'),
          ),
        ],
      ),
    );
  }
}
