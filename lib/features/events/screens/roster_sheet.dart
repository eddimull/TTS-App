import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/cache/cache_invalidator.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/events_repository.dart';
import '../data/models/event_detail.dart';
import '../data/models/event_member.dart';
import '../data/models/sub_entry.dart';
import '../providers/events_provider.dart';

/// Full-screen roster sheet (Task 5). Relocated from the event detail
/// screen's inline `_RosterSection` — the summary row on the detail screen
/// now pushes this instead of rendering the grouped list inline. All
/// grouping/status/sub-assignment behavior below is unchanged from the
/// original section, just moved here.
class RosterSheet extends ConsumerStatefulWidget {
  const RosterSheet({super.key, required this.event});

  final EventDetail event;

  @override
  ConsumerState<RosterSheet> createState() => _RosterSheetState();
}

class _RosterSheetState extends ConsumerState<RosterSheet> {
  @override
  Widget build(BuildContext context) {
    final event = widget.event;

    // Group members by section (BandRole), preserving insertion order.
    final grouped = <String, List<EventMember>>{};
    for (final m in event.members) {
      (grouped[m.groupKey] ??= []).add(m);
    }

    final dateFmt = DateFormat('EEE, MMM d');
    final subtitle = '${event.title} · ${dateFmt.format(event.parsedDate)}';

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Event Roster'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.xmark_circle_fill),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: context.secondaryText),
            ),
            const SizedBox(height: 16),
            ...grouped.entries.map(
              (entry) => _RoleGroup(
                role: entry.key,
                members: entry.value,
                event: event,
                onAssignSub: (member) => _showSubPicker(member),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSubPicker(EventMember member) async {
    if (member.bandRoleId == null) return;
    final event = widget.event;

    // showCupertinoModalPopup creates a new route with a fresh widget tree,
    // so the ProviderScope ancestor is lost. Re-attach the existing
    // container via UncontrolledProviderScope so the sheet reads the same
    // providers (eventSubsProvider, etc).
    final container = ProviderScope.containerOf(context);
    final result = await showCupertinoModalPopup<_SubPickerResult>(
      context: context,
      builder: (sheetContext) => UncontrolledProviderScope(
        container: container,
        child: _SubPickerSheet(event: event, member: member),
      ),
    );

    if (result == null || !mounted) return;

    final repo = ref.read(eventsRepositoryProvider);
    // For synthetic slots (no EventMember row yet), memberId = 0 triggers creation.
    final memberId = member.id ?? 0;

    if (result.clear) {
      await repo.assignSub(event.key, memberId, slotId: member.slotId, clear: true);
    } else if (result.sub != null) {
      final sub = result.sub!;
      await repo.assignSub(
        event.key,
        memberId,
        slotId: member.slotId,
        rosterMemberId: sub.rosterMemberId,
        name: sub.rosterMemberId == null ? sub.name : null,
        email: sub.rosterMemberId == null ? sub.email : null,
      );
    }

    if (mounted) {
      ref.read(cacheInvalidatorProvider).onEventChanged(eventKey: event.key);
    }
  }
}

class _RoleGroup extends StatelessWidget {
  const _RoleGroup({
    required this.role,
    required this.members,
    required this.event,
    required this.onAssignSub,
  });
  final String role;
  final List<EventMember> members;
  final EventDetail event;
  final void Function(EventMember) onAssignSub;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            role.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: context.secondaryText,
            ),
          ),
        ),
        ...members.map(
          (m) => _MemberTile(
            member: m,
            canWrite: event.canWrite,
            onTap: event.canWrite ? () => onAssignSub(m) : null,
          ),
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.canWrite,
    this.onTap,
  });
  final EventMember member;
  final bool canWrite;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final slotLabel = member.slotName;

    if (!member.isFilled) {
      // Unfilled slot — placeholder row with instrument label + add button
      return GestureDetector(
        onTap: canWrite ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemRed
                      .resolveFrom(context)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: CupertinoColors.systemRed
                        .resolveFrom(context)
                        .withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  CupertinoIcons.question_circle,
                  size: 18,
                  color: CupertinoColors.systemRed.resolveFrom(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (slotLabel != null)
                      Text(
                        slotLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.secondaryText,
                        ),
                      ),
                    Text(
                      '— Needed',
                      style: TextStyle(
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                        color: CupertinoColors.systemRed.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (canWrite)
                Icon(
                  CupertinoIcons.add_circled,
                  size: 22,
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                ),
            ],
          ),
        ),
      );
    }

    // Filled slot
    final (icon, iconColor) = switch (member.attendanceStatus?.toLowerCase()) {
      'confirmed' => (
          CupertinoIcons.checkmark_circle_fill,
          CupertinoColors.systemGreen
        ),
      'absent' => (CupertinoIcons.xmark_circle_fill, CupertinoColors.systemRed),
      _ => (CupertinoIcons.circle, CupertinoColors.systemGrey),
    };

    return GestureDetector(
      onTap: canWrite ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemBackground
                    .resolveFrom(context),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                  style:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (slotLabel != null)
                    Text(
                      slotLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.secondaryText,
                      ),
                    ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (member.isSub) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemOrange
                                .resolveFrom(context)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: CupertinoColors.systemOrange
                                  .resolveFrom(context)
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            'Sub',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.systemOrange
                                  .resolveFrom(context),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(icon, size: 20, color: iconColor.resolveFrom(context)),
          ],
        ),
      ),
    );
  }
}

// ── Sub picker sheet ──────────────────────────────────────────────────────────

/// Return value from [_SubPickerSheet].
/// [sub] is set when a sub was selected; [clear] is true when the slot should
/// be cleared. Both null / false means the user dismissed without acting.
class _SubPickerResult {
  const _SubPickerResult({this.sub, this.clear = false});
  final SubEntry? sub;
  final bool clear;
}

/// Bottom sheet showing the substitute call list for a roster slot.
/// Pops with a [_SubPickerResult] so the caller controls all async work.
class _SubPickerSheet extends ConsumerWidget {
  const _SubPickerSheet({required this.event, required this.member});

  final EventDetail event;
  final EventMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subsAsync = ref.watch(
      eventSubsProvider(
          (eventKey: event.key, bandRoleId: member.bandRoleId!)),
    );

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey3.resolveFrom(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Sheet title row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add Sub — ${member.slotName ?? member.role ?? 'Member'}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                if (member.isFilled)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context)
                        .pop(const _SubPickerResult(clear: true)),
                    child: Text(
                      'Clear',
                      style: TextStyle(
                          color: CupertinoColors.systemRed.resolveFrom(context)),
                    ),
                  ),
                CupertinoButton(
                  padding: const EdgeInsets.only(left: 8),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Icon(CupertinoIcons.xmark_circle_fill, size: 24),
                ),
              ],
            ),
          ),
          Container(
              height: 0.5,
              color: CupertinoColors.separator.resolveFrom(context)),
          // Sub list
          Expanded(
            child: subsAsync.when(
              loading: () =>
                  const Center(child: CupertinoActivityIndicator()),
              error: (e, _) => Center(
                child: Text(
                  ErrorView.friendlyMessage(e),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: context.secondaryText),
                ),
              ),
              data: (subs) {
                if (subs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No substitutes on call list for this role.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: context.secondaryText),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: subs.length,
                  separatorBuilder: (_, __) => Container(
                    height: 0.5,
                    margin: const EdgeInsets.only(left: 16),
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  itemBuilder: (context, index) {
                    final sub = subs[index];
                    return CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      onPressed: () => Navigator.of(context)
                          .pop(_SubPickerResult(sub: sub)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      sub.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: context.primaryText,
                                      ),
                                    ),
                                    if (sub.isCustom) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: CupertinoColors.systemOrange
                                              .resolveFrom(context)
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Sub',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: CupertinoColors.systemOrange
                                                .resolveFrom(context),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (sub.email != null && sub.email!.isNotEmpty)
                                  Text(
                                    sub.email!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: context.secondaryText,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            CupertinoIcons.add,
                            size: 20,
                            color:
                                CupertinoColors.systemGreen.resolveFrom(context),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
