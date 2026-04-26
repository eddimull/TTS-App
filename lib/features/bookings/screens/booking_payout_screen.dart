import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/models/booking_payout.dart';
import '../providers/bookings_provider.dart';

class BookingPayoutScreen extends ConsumerWidget {
  const BookingPayoutScreen({
    super.key,
    required this.bandId,
    required this.bookingId,
  });

  final int bandId;
  final int bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (bandId: bandId, bookingId: bookingId);
    final payoutAsync = ref.watch(bookingPayoutProvider(args));

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Payout Breakdown'),
      ),
      child: SafeArea(
        child: payoutAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => ErrorView(
            message: ErrorView.friendlyMessage(e),
            onRetry: () => ref.invalidate(bookingPayoutProvider(args)),
          ),
          data: (payout) => _PayoutView(payout: payout),
        ),
      ),
    );
  }
}

class _PayoutView extends StatelessWidget {
  const _PayoutView({required this.payout});
  final BookingPayout payout;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            const SizedBox(height: 12),

            // ── Configuration row ───────────────────────────────────────
            if (payout.configurationName != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ConfigurationCard(payout: payout),
              ),

            // ── Totals card ─────────────────────────────────────────────
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _TotalsCard(payout: payout),
            ),

            // ── Adjustments ─────────────────────────────────────────────
            if (payout.adjustments.isNotEmpty) ...[
              const SizedBox(height: 24),
              const _SectionHeader(label: 'Adjustments'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _AdjustmentsCard(adjustments: payout.adjustments),
              ),
            ],

            // ── Member payouts ──────────────────────────────────────────
            const SizedBox(height: 24),
            const _SectionHeader(label: 'Member Payouts'),
            if (payout.members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: const _EmptyHint(
                  text: 'No member payouts available for this booking.',
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: CupertinoColors.tertiarySystemBackground
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < payout.members.length; i++)
                        _MemberRow(
                          member: payout.members[i],
                          isLast: i == payout.members.length - 1,
                        ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 32),
          ]),
        ),
      ],
    );
  }
}

// ── Configuration card ────────────────────────────────────────────────────────

class _ConfigurationCard extends StatelessWidget {
  const _ConfigurationCard({required this.payout});
  final BookingPayout payout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.slider_horizontal_3,
              size: 18,
              color: CupertinoColors.secondaryLabel.resolveFrom(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payout Configuration',
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  payout.configurationName ?? '—',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          if (payout.configurationActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGreen
                    .resolveFrom(context)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Active',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.systemGreen.resolveFrom(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Totals card ───────────────────────────────────────────────────────────────

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.payout});
  final BookingPayout payout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StackedAmount(
            label: 'Total Booking Amount',
            value: payout.displayTotal,
            color: CupertinoColors.label.resolveFrom(context),
          ),
          const SizedBox(height: 14),
          const _Divider(),
          const SizedBox(height: 14),
          _StackedAmount(
            label: 'Band Cut',
            value: payout.displayBandCut,
            color: CupertinoColors.systemOrange.resolveFrom(context),
            sublabel: payout.bandCutDescription,
          ),
          const SizedBox(height: 14),
          const _Divider(),
          const SizedBox(height: 14),
          _StackedAmount(
            label: 'Distributable to Members',
            value: payout.displayDistributable,
            color: CupertinoColors.systemBlue.resolveFrom(context),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      color: CupertinoColors.separator.resolveFrom(context),
    );
  }
}

class _StackedAmount extends StatelessWidget {
  const _StackedAmount({
    required this.label,
    required this.value,
    required this.color,
    this.sublabel,
  });

  final String label;
  final String value;
  final Color color;
  final String? sublabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        if (sublabel != null && sublabel!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            sublabel!,
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Adjustments ───────────────────────────────────────────────────────────────

class _AdjustmentsCard extends StatelessWidget {
  const _AdjustmentsCard({required this.adjustments});
  final List<BookingPayoutAdjustment> adjustments;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < adjustments.length; i++)
            _AdjustmentRow(
              adjustment: adjustments[i],
              isLast: i == adjustments.length - 1,
            ),
        ],
      ),
    );
  }
}

class _AdjustmentRow extends StatelessWidget {
  const _AdjustmentRow({required this.adjustment, required this.isLast});

  final BookingPayoutAdjustment adjustment;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: CupertinoColors.separator.resolveFrom(context),
                  width: 0.5,
                ),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(adjustment.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                if (adjustment.type != null && adjustment.type!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      adjustment.type!,
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.secondaryLabel
                            .resolveFrom(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            adjustment.displayAmount,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Member payout row ─────────────────────────────────────────────────────────

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.isLast});

  final BookingPayoutMember member;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final highlight = member.isCurrentUser
        ? CupertinoColors.systemBlue
            .resolveFrom(context)
            .withValues(alpha: 0.08)
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: highlight,
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(12))
            : null,
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: CupertinoColors.separator.resolveFrom(context),
                  width: 0.5,
                ),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (member.isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Icon(
                        CupertinoIcons.person_fill,
                        size: 12,
                        color: CupertinoColors.systemBlue.resolveFrom(context),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                _MemberMeta(member: member),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            member.displayAmount,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.systemGreen.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberMeta extends StatelessWidget {
  const _MemberMeta({required this.member});
  final BookingPayoutMember member;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (member.role != null && member.role!.isNotEmpty) member.role!,
      if (member.type != null && member.type!.isNotEmpty)
        _capitalise(member.type!),
      if (member.attendance != null && member.attendance!.isNotEmpty)
        member.attendance!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join('  •  '),
      style: TextStyle(
        fontSize: 12,
        color: CupertinoColors.secondaryLabel.resolveFrom(context),
      ),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}
