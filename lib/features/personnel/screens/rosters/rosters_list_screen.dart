import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/roster.dart';
import '../../providers/rosters_provider.dart';
import 'roster_detail_screen.dart';

class RostersListScreen extends ConsumerWidget {
  const RostersListScreen({super.key, required this.bandId});

  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const navBar = CupertinoNavigationBar(middle: Text('Rosters'));
    final rostersAsync = ref.watch(rostersProvider(bandId));

    if (rostersAsync.isLoading && !rostersAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    if (rostersAsync.hasError && !rostersAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(
          child: Center(
            child: Text(
              'Failed to load rosters.',
              style: TextStyle(color: CupertinoColors.secondaryLabel),
            ),
          ),
        ),
      );
    }

    final rosters = rostersAsync.value!;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Rosters'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _showCreateDialog(context, ref),
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      child: SafeArea(
        child: rosters.isEmpty
            ? Center(
                child: Text(
                  'No rosters yet. Tap + to create one.',
                  style: TextStyle(
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              )
            : ListView(
                children: [
                  CupertinoListSection.insetGrouped(
                    children: [
                      for (final roster in rosters)
                        _RosterRow(roster: roster, bandId: bandId),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('New Roster'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: nameController,
              placeholder: 'Roster name',
              autofocus: true,
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: descController,
              placeholder: 'Description (optional)',
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final name = nameController.text.trim();
              final desc = descController.text.trim();
              Navigator.of(dialogContext).pop();
              if (name.isEmpty) return;
              try {
                await ref.read(rostersProvider(bandId).notifier).createRoster(
                      name,
                      description: desc.isNotEmpty ? desc : null,
                    );
              } catch (_) {
                if (context.mounted) {
                  showCupertinoDialog<void>(
                    context: context,
                    builder: (d) => CupertinoAlertDialog(
                      title: const Text('Error'),
                      content: const Text('Failed to create roster.'),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.of(d).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    nameController.dispose();
    descController.dispose();
  }
}

class _RosterRow extends ConsumerWidget {
  const _RosterRow({required this.roster, required this.bandId});

  final Roster roster;
  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('roster-${roster.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context, ref),
      background: Container(
        color: CupertinoColors.destructiveRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
      ),
      child: CupertinoListTile(
        title: Row(
          children: [
            Text(roster.name),
            if (roster.isDefault) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CupertinoColors.activeBlue
                      .resolveFrom(context)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Default',
                  style: TextStyle(
                    fontSize: 11,
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
            '${roster.membersCount} member${roster.membersCount == 1 ? '' : 's'}'),
        trailing: const CupertinoListTileChevron(),
        onTap: () => Navigator.of(context).push(
          CupertinoPageRoute<void>(
            builder: (_) => RosterDetailScreen(
              bandId: bandId,
              rosterId: roster.id,
              rosterName: roster.name,
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        title: const Text('Delete Roster'),
        content: Text('Delete "${roster.name}"?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Delete'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;
    try {
      await ref.read(rostersProvider(bandId).notifier).deleteRoster(roster.id);
    } catch (_) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (d) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to delete roster.'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(d).pop(),
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
