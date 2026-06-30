import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/contacts/contact_detail_screen.dart';
import '../../../../features/contacts/contact_ref.dart';
import '../../data/models/roster.dart';
import '../../providers/roles_provider.dart';
import '../../providers/rosters_provider.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

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
        child: SafeArea(
          child: Center(
            child: Text(
              'Failed to load roster details.',
              style: TextStyle(color: context.secondaryText),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _showReconcileDialog(context, ref),
              child: const Icon(CupertinoIcons.arrow_2_squarepath),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _showAddMemberDialog(context, ref, roster),
              child: const Icon(CupertinoIcons.person_badge_plus),
            ),
          ],
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
                      CupertinoListTile(
                        title: Text(
                          'No slots defined',
                          style: TextStyle(
                              color: context.secondaryText),
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
                      color: context.secondaryText,
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
    var applyToFutureEvents = false;

    await showCupertinoDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setState) => CupertinoAlertDialog(
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
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Add to future events using this roster',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  CupertinoSwitch(
                    value: applyToFutureEvents,
                    onChanged: (v) => setState(() => applyToFutureEvents = v),
                  ),
                ],
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
                        applyToFutureEvents: applyToFutureEvents,
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
      ),
    );
    nameController.dispose();
    emailController.dispose();
  }

  Future<void> _showReconcileDialog(
      BuildContext context, WidgetRef ref) async {
    final RosterEventDiff diff;
    try {
      diff = await ref
          .read(personnelRepositoryProvider)
          .getFutureEventsDiff(bandId, rosterId);
    } catch (_) {
      if (context.mounted) {
        _showError(context, 'Failed to load future event differences.');
      }
      return;
    }
    if (!context.mounted) return;

    if (diff.isEmpty) {
      _showInfo(
        context,
        'In Sync',
        'Future events are already in sync with this roster.',
      );
      return;
    }

    final removeIds = <int>{};
    final addIds = <int>{};
    var applying = false;

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (popupContext) => StatefulBuilder(
        builder: (context, setState) {
          Widget entryTile(RosterEventDiffEntry e, Set<int> selection) {
            final id = e.rosterMemberId;
            final selectable = id != null;
            return CupertinoListTile(
              title: Text(e.displayName),
              subtitle: Text(
                '${e.eventCount} event${e.eventCount == 1 ? '' : 's'}',
              ),
              trailing: selectable
                  ? CupertinoSwitch(
                      value: selection.contains(id),
                      onChanged: (v) => setState(() {
                        if (v) {
                          selection.add(id);
                        } else {
                          selection.remove(id);
                        }
                      }),
                    )
                  : Text(
                      'n/a',
                      style: TextStyle(color: context.tertiaryText),
                    ),
            );
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            color: CupertinoColors.systemBackground.resolveFrom(context),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: applying
                              ? null
                              : () => Navigator.of(popupContext).pop(),
                          child: const Text('Cancel'),
                        ),
                        const Text(
                          'Sync future events',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed:
                              (applying || (removeIds.isEmpty && addIds.isEmpty))
                                  ? null
                                  : () async {
                                      setState(() => applying = true);
                                      try {
                                        await ref
                                            .read(personnelRepositoryProvider)
                                            .reconcileFutureEvents(
                                              bandId,
                                              rosterId,
                                              removeMemberIds: removeIds.toList(),
                                              addMemberIds: addIds.toList(),
                                            );
                                        ref.invalidate(
                                          rosterDetailProvider((
                                            bandId: bandId,
                                            rosterId: rosterId
                                          )),
                                        );
                                        // Close only after the request succeeds.
                                        if (popupContext.mounted) {
                                          Navigator.of(popupContext).pop();
                                        }
                                      } catch (_) {
                                        // Show the error while the modal (and
                                        // its context) is still mounted.
                                        if (popupContext.mounted) {
                                          setState(() => applying = false);
                                          _showError(popupContext,
                                              'Failed to update future events.');
                                        }
                                      }
                                    },
                          child: applying
                              ? const CupertinoActivityIndicator()
                              : const Text('Apply'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        if (diff.extra.isNotEmpty)
                          CupertinoListSection.insetGrouped(
                            header: const Text(
                                'ON FUTURE EVENTS BUT NOT ON THE ROSTER'),
                            children: diff.extra
                                .map((e) => entryTile(e, removeIds))
                                .toList(),
                          ),
                        if (diff.missing.isNotEmpty)
                          CupertinoListSection.insetGrouped(
                            header: const Text(
                                'ON THE ROSTER BUT MISSING FROM FUTURE EVENTS'),
                            children: diff.missing
                                .map((e) => entryTile(e, addIds))
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showError(BuildContext context, String message) =>
      _showInfo(context, 'Error', message);

  void _showInfo(BuildContext context, String title, String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        title: Text(title),
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
            color: context.secondaryText,
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

    // Ask whether to also remove this person from future events.
    final applyToFuture = await showCupertinoDialog<bool>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        title: const Text('Future Events'),
        content: Text(
          'Also remove ${member.name} from future events using this roster?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Roster only'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Remove from events'),
          ),
        ],
      ),
    );
    if (!context.mounted) return false;

    try {
      await ref.read(personnelRepositoryProvider).removeRosterMember(
            bandId,
            member.id,
            applyToFutureEvents: applyToFuture ?? false,
          );
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
