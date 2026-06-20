import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/contacts/contact_detail_screen.dart';
import '../../../../features/contacts/contact_ref.dart';
import '../../data/models/roster.dart';
import '../../providers/roles_provider.dart';
import '../../providers/rosters_provider.dart';

class RosterDetailScreen extends ConsumerWidget {
  const RosterDetailScreen({
    super.key,
    required this.bandId,
    required this.rosterId,
    required this.rosterName,
  });

  final int bandId;
  final int rosterId;
  final String rosterName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navBar = CupertinoNavigationBar(middle: Text(rosterName));
    final detailAsync = ref.watch(
      rosterDetailProvider((bandId: bandId, rosterId: rosterId)),
    );

    if (detailAsync.isLoading && !detailAsync.hasValue) {
      return CupertinoPageScaffold(
        navigationBar: navBar,
        child: const SafeArea(
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }

    if (detailAsync.hasError && !detailAsync.hasValue) {
      return CupertinoPageScaffold(
        navigationBar: navBar,
        child: const SafeArea(
          child: Center(
            child: Text(
              'Failed to load roster details.',
              style: TextStyle(color: CupertinoColors.secondaryLabel),
            ),
          ),
        ),
      );
    }

    final roster = detailAsync.value!;

    // Group members by slotId; null slot = unassigned.
    final bySlot = <int?, List<RosterMember>>{};
    for (final m in roster.members) {
      bySlot.putIfAbsent(m.slotId, () => []).add(m);
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(rosterName),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _showAddMemberDialog(context, ref, roster),
          child: const Icon(CupertinoIcons.person_badge_plus),
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            // ── Slots section ─────────────────────────────────────────────
            CupertinoListSection.insetGrouped(
              header: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('SLOTS'),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => _showAddSlotDialog(context, ref),
                    child: const Text(
                      'Add',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              children: roster.slots.isEmpty
                  ? [
                      const CupertinoListTile(
                        title: Text(
                          'No slots defined',
                          style: TextStyle(
                              color: CupertinoColors.secondaryLabel),
                        ),
                      ),
                    ]
                  : [
                      for (final slot in roster.slots)
                        _SlotRow(
                          slot: slot,
                          bandId: bandId,
                          rosterId: rosterId,
                        ),
                    ],
            ),

            // ── Members grouped by slot ──────────────────────────────────
            for (final slot in roster.slots)
              if (bySlot.containsKey(slot.id))
                CupertinoListSection.insetGrouped(
                  header: Text(slot.name.toUpperCase()),
                  children: [
                    for (final member in bySlot[slot.id]!)
                      _MemberRow(
                        member: member,
                        bandId: bandId,
                        rosterId: rosterId,
                      ),
                  ],
                ),

            // ── Unassigned members ───────────────────────────────────────
            if ((bySlot[null] ?? []).isNotEmpty)
              CupertinoListSection.insetGrouped(
                header: const Text('GENERAL'),
                children: [
                  for (final member in bySlot[null]!)
                    _MemberRow(
                      member: member,
                      bandId: bandId,
                      rosterId: rosterId,
                    ),
                ],
              ),

            if (roster.members.isEmpty && roster.slots.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No members yet. Tap the person+ icon to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddSlotDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    await showCupertinoDialog<void>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        title: const Text('Add Slot'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Slot name (e.g. Lead Trumpet)',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(d).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final name = controller.text.trim();
              Navigator.of(d).pop();
              if (name.isEmpty) return;
              try {
                await ref
                    .read(personnelRepositoryProvider)
                    .createSlot(bandId, rosterId, name: name);
                ref.invalidate(
                  rosterDetailProvider((bandId: bandId, rosterId: rosterId)),
                );
              } catch (_) {
                if (context.mounted) {
                  _showError(context, 'Failed to add slot.');
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _showAddMemberDialog(
      BuildContext context, WidgetRef ref, Roster roster) async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();

    await showCupertinoDialog<void>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        title: const Text('Add Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: nameController,
              placeholder: 'Name',
              autofocus: true,
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: emailController,
              placeholder: 'Email (optional)',
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(d).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final name = nameController.text.trim();
              final email = emailController.text.trim();
              Navigator.of(d).pop();
              if (name.isEmpty) return;
              try {
                await ref.read(personnelRepositoryProvider).addRosterMember(
                      bandId,
                      rosterId,
                      name: name,
                      email: email.isNotEmpty ? email : null,
                    );
                ref.invalidate(
                  rosterDetailProvider((bandId: bandId, rosterId: rosterId)),
                );
              } catch (_) {
                if (context.mounted) {
                  _showError(context, 'Failed to add member.');
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    nameController.dispose();
    emailController.dispose();
  }

  void _showError(BuildContext context, String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
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

// ── Slot row ──────────────────────────────────────────────────────────────────

class _SlotRow extends ConsumerWidget {
  const _SlotRow({
    required this.slot,
    required this.bandId,
    required this.rosterId,
  });

  final RosterSlot slot;
  final int bandId;
  final int rosterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('slot-${slot.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context, ref),
      background: Container(
        color: CupertinoColors.destructiveRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
      ),
      child: CupertinoListTile(
        title: Text(slot.name),
        subtitle: slot.bandRoleName != null ? Text(slot.bandRoleName!) : null,
        additionalInfo: Text(
          '${slot.memberCount}/${slot.quantity}',
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        title: const Text('Delete Slot'),
        content: Text('Delete slot "${slot.name}"?'),
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
      await ref.read(personnelRepositoryProvider).deleteSlot(bandId, slot.id);
      ref.invalidate(
        rosterDetailProvider((bandId: bandId, rosterId: rosterId)),
      );
    } catch (_) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (d) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to delete slot.'),
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

// ── Member row ────────────────────────────────────────────────────────────────

class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.member,
    required this.bandId,
    required this.rosterId,
  });

  final RosterMember member;
  final int bandId;
  final int rosterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('roster-member-${member.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmRemove(context, ref),
      background: Container(
        color: CupertinoColors.destructiveRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
      ),
      child: CupertinoListTile(
        leading: ClipOval(
          child: Container(
            width: 36,
            height: 36,
            color: member.isActive
                ? CupertinoColors.systemGrey4
                : CupertinoColors.systemGrey5,
            alignment: Alignment.center,
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: member.isActive
                    ? CupertinoColors.white
                    : CupertinoColors.systemGrey,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ),
        title: Text(
          member.name,
          style: TextStyle(
            color: member.isActive
                ? null
                : CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        subtitle: member.role != null ? Text(member.role!) : null,
        trailing: const CupertinoListTileChevron(),
        onTap: () => Navigator.of(context).push(
          CupertinoPageRoute<void>(
            builder: (_) => ContactDetailScreen(
              contact: ContactRef(
                name: member.name,
                email: member.email,
                phone: member.phone,
                role: member.role,
                userId: member.userId,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.name} from this roster?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Remove'),
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
      await ref
          .read(personnelRepositoryProvider)
          .removeRosterMember(bandId, member.id);
      ref.invalidate(
        rosterDetailProvider((bandId: bandId, rosterId: rosterId)),
      );
    } catch (_) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (d) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to remove member.'),
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
