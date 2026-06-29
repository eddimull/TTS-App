import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/band_role.dart';
import '../../providers/roles_provider.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

class RolesScreen extends ConsumerWidget {
  const RolesScreen({super.key, required this.bandId});

  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const navBar = CupertinoNavigationBar(middle: Text('Roles'));
    final rolesAsync = ref.watch(rolesProvider(bandId));

    if (rolesAsync.isLoading && !rolesAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    if (rolesAsync.hasError && !rolesAsync.hasValue) {
      return CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(
          child: Center(
            child: Text(
              'Failed to load roles.',
              style: TextStyle(color: context.secondaryText),
            ),
          ),
        ),
      );
    }

    final roles = rolesAsync.value!;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Roles'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _showCreateDialog(context, ref),
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      child: SafeArea(
        child: roles.isEmpty
            ? Center(
                child: Text(
                  'No roles yet. Tap + to create one.',
                  style: TextStyle(
                    color: context.secondaryText,
                  ),
                ),
              )
            : ListView(
                children: [
                  CupertinoListSection.insetGrouped(
                    header: const Text('Band Roles'),
                    children: [
                      for (final role in roles)
                        _RoleRow(role: role, bandId: bandId),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('New Role'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Role name',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final name = controller.text.trim();
              Navigator.of(dialogContext).pop();
              if (name.isEmpty) return;
              try {
                await ref.read(rolesProvider(bandId).notifier).createRole(name);
              } catch (_) {
                if (context.mounted) {
                  showCupertinoDialog<void>(
                    context: context,
                    builder: (d) => CupertinoAlertDialog(
                      title: const Text('Error'),
                      content: const Text('Failed to create role.'),
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
    controller.dispose();
  }
}

class _RoleRow extends ConsumerWidget {
  const _RoleRow({required this.role, required this.bandId});

  final BandRole role;
  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = [
      if (role.rosterMembersCount > 0) '${role.rosterMembersCount} roster',
      if (role.eventMembersCount > 0) '${role.eventMembersCount} event',
    ].join(' · ');

    return Dismissible(
      key: ValueKey('role-${role.id}'),
      direction: role.rosterMembersCount > 0 || role.eventMembersCount > 0
          ? DismissDirection.none
          : DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context, ref),
      background: Container(
        color: CupertinoColors.destructiveRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
      ),
      child: CupertinoListTile(
        title: Text(role.name),
        subtitle: counts.isNotEmpty ? Text(counts) : null,
        additionalInfo: role.isActive
            ? null
            : Text(
                'Inactive',
                style: TextStyle(
                  color: context.secondaryText,
                  fontSize: 13,
                ),
              ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _showEditDialog(context, ref),
          child: Icon(
            CupertinoIcons.ellipsis,
            color: context.secondaryText,
            size: 20,
          ),
        ),
        onTap: () => _showEditDialog(context, ref),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        title: const Text('Delete Role'),
        content: Text('Delete "${role.name}"?'),
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
      await ref.read(rolesProvider(bandId).notifier).deleteRole(role.id);
    } catch (_) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (d) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to delete role.'),
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

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: role.name);
    var isActive = role.isActive;

    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) => CupertinoAlertDialog(
          title: const Text('Edit Role'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: controller,
                placeholder: 'Role name',
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Active'),
                  CupertinoSwitch(
                    value: isActive,
                    onChanged: (v) => setState(() => isActive = v),
                  ),
                ],
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
                final name = controller.text.trim();
                Navigator.of(dialogContext).pop();
                try {
                  await ref.read(rolesProvider(bandId).notifier).updateRole(
                        role.id,
                        name: name.isNotEmpty ? name : null,
                        isActive: isActive,
                      );
                } catch (_) {
                  if (context.mounted) {
                    showCupertinoDialog<void>(
                      context: context,
                      builder: (d) => CupertinoAlertDialog(
                        title: const Text('Error'),
                        content: const Text('Failed to update role.'),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }
}
