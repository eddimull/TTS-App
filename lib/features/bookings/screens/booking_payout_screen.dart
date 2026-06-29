import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../../auth/providers/auth_provider.dart';
import '../data/models/booking_payout.dart';
import '../providers/booking_payout_provider.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

class BookingPayoutScreen extends ConsumerWidget {
  const BookingPayoutScreen({
    required this.bandId,
    required this.bookingId,
    super.key,
  });

  final int bandId;
  final int bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (bandId: bandId, bookingId: bookingId);
    final payoutAsync = ref.watch(bookingPayoutProvider(key));

    // Derive current user id for the "you" highlight in member rows.
    final authState = ref.watch(authProvider).value;
    final currentUserId =
        authState is AuthAuthenticated ? authState.user.id : null;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Payout'),
      ),
      child: SafeArea(
        child: payoutAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) =>
              ErrorView(message: ErrorView.friendlyMessage(e)),
          data: (payout) => _PayoutBody(
            payout: payout,
            bandId: bandId,
            bookingId: bookingId,
            currentUserId: currentUserId,
            notifierKey: key,
            ref: ref,
          ),
        ),
      ),
    );
  }
}

// ── Scrollable body ───────────────────────────────────────────────────────────

class _PayoutBody extends StatelessWidget {
  const _PayoutBody({
    required this.payout,
    required this.bandId,
    required this.bookingId,
    required this.currentUserId,
    required this.notifierKey,
    required this.ref,
  });

  final BookingPayout payout;
  final int bandId;
  final int bookingId;
  final int? currentUserId;
  final BookingPayoutKey notifierKey;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // 1. Summary card
        SliverToBoxAdapter(child: _SummaryCard(payout: payout)),

        // 2. Config selector
        SliverToBoxAdapter(
          child: _ConfigSelector(
            payout: payout,
            onSelect: (id) => ref
                .read(bookingPayoutProvider(notifierKey).notifier)
                .switchConfig(id),
          ),
        ),

        // 3. Member payouts
        SliverToBoxAdapter(
          child: _MemberPayoutsSection(
            payout: payout,
            currentUserId: currentUserId,
          ),
        ),

        // 4. By performance — only when more than one event
        if (payout.events.length > 1)
          SliverToBoxAdapter(
            child: _ByPerformanceSection(
              events: payout.events,
              currentUserId: currentUserId,
              onSetAttendance: (eventId, memberId, status) => ref
                  .read(bookingPayoutProvider(notifierKey).notifier)
                  .setAttendance(eventId, memberId, status),
            ),
          ),

        // 5. Adjustments
        SliverToBoxAdapter(
          child: _AdjustmentsSection(
            adjustments: payout.adjustments,
            onDelete: (id) => ref
                .read(bookingPayoutProvider(notifierKey).notifier)
                .deleteAdjustment(id),
            onAdd: ({required amount, required description, notes}) => ref
                .read(bookingPayoutProvider(notifierKey).notifier)
                .addAdjustment(
                  amount: amount,
                  description: description,
                  notes: notes,
                ),
          ),
        ),

        // Bottom breathing room for the last section
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

// ── 1. Summary card ───────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.payout});

  final BookingPayout payout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Base price
            _FinRow(
              label: 'Base price',
              value: payout.displayBasePrice,
              bold: true,
            ),

            // Adjustments row only when present
            if (payout.hasAdjustments) ...[
              const SizedBox(height: 6),
              _FinRow(
                label: 'Adjustments',
                value: payout.displayAdjustedTotal,
              ),
            ],

            const SizedBox(height: 12),
            Container(
              height: 0.5,
              color: CupertinoColors.separator.resolveFrom(context),
            ),
            const SizedBox(height: 12),

            // Three stat tiles
            Row(
              children: [
                _StatTile(
                  label: 'Total',
                  value: payout.displayAdjustedTotal,
                ),
                _StatDivider(),
                _StatTile(
                  label: 'Band cut',
                  value: payout.displayBandCut,
                ),
                _StatDivider(),
                _StatTile(
                  label: 'Distributable',
                  value: payout.displayDistributable,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FinRow extends StatelessWidget {
  const _FinRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final weight = bold ? FontWeight.w600 : FontWeight.normal;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 15, fontWeight: weight)),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: weight)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 36,
      color: CupertinoColors.separator.resolveFrom(context),
    );
  }
}

// ── 2. Config selector ────────────────────────────────────────────────────────

class _ConfigSelector extends StatelessWidget {
  const _ConfigSelector({
    required this.payout,
    required this.onSelect,
  });

  final BookingPayout payout;
  final void Function(int configId) onSelect;

  @override
  Widget build(BuildContext context) {
    final config = payout.config;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: config == null
          ? _NoConfigWarning()
          : _ActiveConfigRow(
              config: config,
              availableConfigs: payout.availableConfigs,
              onSelect: onSelect,
            ),
    );
  }
}

class _NoConfigWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemYellow.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CupertinoColors.systemYellow.resolveFrom(context),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 18,
            color: CupertinoColors.systemOrange.resolveFrom(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No active payout configuration',
              style: TextStyle(
                fontSize: 14,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveConfigRow extends StatelessWidget {
  const _ActiveConfigRow({
    required this.config,
    required this.availableConfigs,
    required this.onSelect,
  });

  final PayoutConfigRef config;
  final List<PayoutConfigRef> availableConfigs;
  final void Function(int configId) onSelect;

  void _showPicker(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Payout Configuration'),
        actions: availableConfigs.map((c) {
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              if (c.id != config.id) {
                onSelect(c.id);
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(c.name),
                if (c.id == config.id) ...[
                  const SizedBox(width: 8),
                  const _ActiveBadge(),
                ],
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:
              CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.settings,
              size: 18,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                config.name,
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const _ActiveBadge(),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGreen.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: CupertinoColors.systemGreen.resolveFrom(context),
          width: 0.5,
        ),
      ),
      child: Text(
        'Active',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: CupertinoColors.systemGreen.resolveFrom(context),
        ),
      ),
    );
  }
}

// ── 3. Member payouts ─────────────────────────────────────────────────────────

class _MemberPayoutsSection extends StatelessWidget {
  const _MemberPayoutsSection({
    required this.payout,
    required this.currentUserId,
  });

  final BookingPayout payout;
  final int? currentUserId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Member Payouts',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                letterSpacing: 0.4,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color:
                  CupertinoColors.tertiarySystemBackground.resolveFrom(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: payout.groups.isNotEmpty
                ? _GroupedMembers(
                    groups: payout.groups,
                    currentUserId: currentUserId,
                  )
                : _FlatMembers(
                    members: payout.members,
                    currentUserId: currentUserId,
                  ),
          ),
        ],
      ),
    );
  }
}

class _GroupedMembers extends StatelessWidget {
  const _GroupedMembers({
    required this.groups,
    required this.currentUserId,
  });

  final List<PayoutGroup> groups;
  final int? currentUserId;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var gi = 0; gi < groups.length; gi++) {
      final group = groups[gi];

      // Group header row
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                group.groupName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                group.displayTotal,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );

      for (var mi = 0; mi < group.members.length; mi++) {
        final member = group.members[mi];
        final isLast =
            mi == group.members.length - 1 && gi == groups.length - 1;
        children.add(_MemberRow(
          member: member,
          isCurrentUser: currentUserId != null &&
              member.userId != null &&
              member.userId == currentUserId,
          showDivider: !isLast,
        ));
      }
    }
    return Column(children: children);
  }
}

class _FlatMembers extends StatelessWidget {
  const _FlatMembers({
    required this.members,
    required this.currentUserId,
  });

  final List<MemberPayout> members;
  final int? currentUserId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(members.length, (i) {
        final member = members[i];
        return _MemberRow(
          member: member,
          isCurrentUser: currentUserId != null &&
              member.userId != null &&
              member.userId == currentUserId,
          showDivider: i < members.length - 1,
        );
      }),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isCurrentUser,
    required this.showDivider,
  });

  final MemberPayout member;
  final bool isCurrentUser;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final highlight = isCurrentUser;
    return Container(
      decoration: BoxDecoration(
        color: highlight
            ? CupertinoColors.activeBlue.withValues(alpha: 0.07)
            : null,
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: CupertinoColors.separator.resolveFrom(context),
                  width: 0.5,
                ),
              )
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      member.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: highlight
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Text(
                        'You',
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.activeBlue
                              .resolveFrom(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
                if (member.role != null || member.attendanceLabel != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (member.role != null)
                        Text(
                          member.role!,
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                      if (member.role != null &&
                          member.attendanceLabel != null)
                        Text(
                          '  ·  ',
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                      if (member.attendanceLabel != null)
                        Text(
                          member.attendanceLabel!,
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Text(
            member.displayAmount,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 4. By performance ─────────────────────────────────────────────────────────

const _kAttendanceStatuses = [
  ('confirmed', 'Confirmed'),
  ('attended', 'Attended'),
  ('absent', 'Absent'),
  ('excused', 'Excused'),
];

class _ByPerformanceSection extends StatelessWidget {
  const _ByPerformanceSection({
    required this.events,
    required this.currentUserId,
    required this.onSetAttendance,
  });

  final List<PayoutEvent> events;
  final int? currentUserId;
  final Future<void> Function(int eventId, int memberId, String status)
      onSetAttendance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'By Performance',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                letterSpacing: 0.4,
              ),
            ),
          ),
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _EventCard(
                event: event,
                currentUserId: currentUserId,
                onSetAttendance: onSetAttendance,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.currentUserId,
    required this.onSetAttendance,
  });

  final PayoutEvent event;
  final int? currentUserId;
  final Future<void> Function(int eventId, int memberId, String status)
      onSetAttendance;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:
            CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    event.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  event.displayValue,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          Container(
            height: 0.5,
            color: CupertinoColors.separator.resolveFrom(context),
          ),

          // Member rows with attendance pills
          ...List.generate(event.members.length, (i) {
            final member = event.members[i];
            final isLast = i == event.members.length - 1;
            return _EventMemberRow(
              member: member,
              isCurrentUser: currentUserId != null &&
                  member.userId != null &&
                  member.userId == currentUserId,
              showDivider: !isLast,
              onTap: () => _showAttendancePicker(context, event.id, member),
            );
          }),
        ],
      ),
    );
  }

  void _showAttendancePicker(
    BuildContext context,
    int eventId,
    PayoutEventMember member,
  ) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(member.name),
        message: const Text('Set attendance status'),
        actions: _kAttendanceStatuses.map((s) {
          final isSelected = s.$1 == member.attendanceStatus;
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              if (!isSelected) {
                onSetAttendance(eventId, member.id, s.$1);
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(s.$2),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.checkmark, size: 16),
                ],
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

class _EventMemberRow extends StatelessWidget {
  const _EventMemberRow({
    required this.member,
    required this.isCurrentUser,
    required this.showDivider,
    required this.onTap,
  });

  final PayoutEventMember member;
  final bool isCurrentUser;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: showDivider
              ? Border(
                  bottom: BorderSide(
                    color:
                        CupertinoColors.separator.resolveFrom(context),
                    width: 0.5,
                  ),
                )
              : null,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    member.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isCurrentUser
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  if (isCurrentUser) ...[
                    const SizedBox(width: 6),
                    Text(
                      'You',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            CupertinoColors.activeBlue.resolveFrom(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _AttendancePill(status: member.attendanceStatus),
          ],
        ),
      ),
    );
  }
}

class _AttendancePill extends StatelessWidget {
  const _AttendancePill({required this.status});

  final String status;

  Color _bgColor(BuildContext context) {
    switch (status) {
      case 'attended':
        return CupertinoColors.systemGreen.withValues(alpha: 0.15);
      case 'absent':
        return CupertinoColors.systemRed.withValues(alpha: 0.15);
      case 'excused':
        return CupertinoColors.systemOrange.withValues(alpha: 0.15);
      case 'confirmed':
      default:
        return CupertinoColors.systemBlue.withValues(alpha: 0.15);
    }
  }

  Color _fgColor(BuildContext context) {
    switch (status) {
      case 'attended':
        return CupertinoColors.systemGreen.resolveFrom(context);
      case 'absent':
        return CupertinoColors.systemRed.resolveFrom(context);
      case 'excused':
        return CupertinoColors.systemOrange.resolveFrom(context);
      case 'confirmed':
      default:
        return CupertinoColors.activeBlue.resolveFrom(context);
    }
  }

  String get _label {
    switch (status) {
      case 'attended':
        return 'Attended';
      case 'absent':
        return 'Absent';
      case 'excused':
        return 'Excused';
      case 'confirmed':
      default:
        return 'Confirmed';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _bgColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _fgColor(context), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _fgColor(context),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            CupertinoIcons.chevron_down,
            size: 10,
            color: _fgColor(context),
          ),
        ],
      ),
    );
  }
}

// ── 5. Adjustments ────────────────────────────────────────────────────────────

class _AdjustmentsSection extends StatelessWidget {
  const _AdjustmentsSection({
    required this.adjustments,
    required this.onDelete,
    required this.onAdd,
  });

  final List<PayoutAdjustment> adjustments;
  final Future<void> Function(int id) onDelete;
  final Future<void> Function({
    required double amount,
    required String description,
    String? notes,
  }) onAdd;

  void _showAddSheet(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _AddAdjustmentSheet(onSaved: onAdd),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PayoutAdjustment adjustment,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Delete Adjustment'),
        content: Text(
          'Delete "${adjustment.description}" (${adjustment.displayAmount})?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await onDelete(adjustment.id);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Adjustments',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      CupertinoColors.secondaryLabel.resolveFrom(context),
                  letterSpacing: 0.4,
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => _showAddSheet(context),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.plus_circle,
                      size: 16,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            CupertinoColors.activeBlue.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (adjustments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No adjustments',
                  style: TextStyle(
                    fontSize: 14,
                    color:
                        CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemBackground
                    .resolveFrom(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: List.generate(adjustments.length, (i) {
                  final adj = adjustments[i];
                  final isLast = i == adjustments.length - 1;
                  return _AdjustmentRow(
                    adjustment: adj,
                    showDivider: !isLast,
                    onDelete: () => _confirmDelete(context, adj),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdjustmentRow extends StatelessWidget {
  const _AdjustmentRow({
    required this.adjustment,
    required this.showDivider,
    required this.onDelete,
  });

  final PayoutAdjustment adjustment;
  final bool showDivider;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: CupertinoColors.separator.resolveFrom(context),
                  width: 0.5,
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  adjustment.description,
                  style: const TextStyle(fontSize: 15),
                ),
                if (adjustment.notes != null &&
                    adjustment.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    adjustment.notes!,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel
                          .resolveFrom(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            adjustment.displayAmount,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: adjustment.amount < 0
                  ? CupertinoColors.systemRed.resolveFrom(context)
                  : CupertinoColors.systemGreen.resolveFrom(context),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: onDelete,
            child: Icon(
              CupertinoIcons.trash,
              size: 18,
              color: CupertinoColors.systemRed.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Add adjustment sheet ──────────────────────────────────────────────────────

class _AddAdjustmentSheet extends StatefulWidget {
  const _AddAdjustmentSheet({required this.onSaved});

  final Future<void> Function({
    required double amount,
    required String description,
    String? notes,
  }) onSaved;

  @override
  State<_AddAdjustmentSheet> createState() => _AddAdjustmentSheetState();
}

class _AddAdjustmentSheetState extends State<_AddAdjustmentSheet> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amountStr = _amountCtrl.text.trim();
    final description = _descCtrl.text.trim();

    if (amountStr.isEmpty || description.isEmpty) return;

    final amount = double.tryParse(amountStr);
    if (amount == null) return;

    setState(() => _saving = true);
    try {
      await widget.onSaved(
        amount: amount,
        description: description,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color:
                        CupertinoColors.systemGrey4.resolveFrom(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header + save button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add Adjustment',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_saving)
                    const CupertinoActivityIndicator()
                  else
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _save,
                      child: const Text(
                        'Save',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Amount field
              CupertinoTextField(
                controller: _amountCtrl,
                placeholder: 'Amount (e.g. -50.00 or 100.00)',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true, signed: true),
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(r'$'),
                ),
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 8),

              // Description field
              CupertinoTextField(
                controller: _descCtrl,
                placeholder: 'Description',
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 8),

              // Notes field (optional)
              CupertinoTextField(
                controller: _notesCtrl,
                placeholder: 'Notes (optional)',
                padding: const EdgeInsets.all(12),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
