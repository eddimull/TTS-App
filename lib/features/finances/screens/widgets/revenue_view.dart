import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../../data/models/band_revenue.dart';
import '../../providers/finances_provider.dart';
import 'revenue_bar_chart.dart';

/// Revenue tab body. Returns a sliver (the parent screen owns the scroll view).
class RevenueView extends ConsumerWidget {
  const RevenueView({super.key, required this.bandId});

  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revenueAsync = ref.watch(revenueProvider(bandId));

    return revenueAsync.when(
      loading: () => const SliverFillRemaining(
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => SliverFillRemaining(
        child: ErrorView(
          message: ErrorView.friendlyMessage(e),
          onRetry: () => ref.read(revenueProvider(bandId).notifier).refresh(),
        ),
      ),
      data: (revenue) {
        if (revenue.years.isEmpty) {
          return const SliverFillRemaining(
            child: EmptyStateView(
              icon: CupertinoIcons.chart_bar,
              title: 'No revenue yet',
              subtitle: 'Recorded payments will appear here.',
            ),
          );
        }
        return SliverList(
          delegate: SliverChildListDelegate([
            const SizedBox(height: 8),
            _SummaryCards(revenue: revenue),
            const SizedBox(height: 12),
            RevenueBarChart(revenue: revenue),
            const SizedBox(height: 12),
            _RevenueTable(revenue: revenue),
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }
}

// ── Summary cards ─────────────────────────────────────────────────────────────

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.revenue});

  final BandRevenue revenue;

  @override
  Widget build(BuildContext context) {
    final currentYear = revenue.currentYearCents;
    final cards = <Widget>[
      _StatCard(
        label: 'Total Revenue',
        value: BandRevenue.formatCents(revenue.totalCents),
        icon: CupertinoIcons.money_dollar,
        tint: CupertinoColors.systemBlue.resolveFrom(context),
      ),
      if (currentYear != null)
        _StatCard(
          label: '${DateTime.now().year} Revenue',
          value: BandRevenue.formatCents(currentYear),
          icon: CupertinoIcons.calendar,
          tint: CupertinoColors.systemGreen.resolveFrom(context),
        ),
      _StatCard(
        label: 'Years Active',
        value: '${revenue.yearsActive}',
        icon: CupertinoIcons.chart_bar_alt_fill,
        tint: CupertinoColors.systemPurple.resolveFrom(context),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tint, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

// ── Revenue-by-year table ─────────────────────────────────────────────────────

class _RevenueTable extends StatelessWidget {
  const _RevenueTable({required this.revenue});

  final BandRevenue revenue;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().year;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color:
                CupertinoColors.secondarySystemBackground.resolveFrom(context),
            child: const Row(
              children: [
                Expanded(flex: 3, child: _HeaderCell('Year')),
                Expanded(flex: 4, child: _HeaderCell('Revenue', alignRight: true)),
                Expanded(flex: 3, child: _HeaderCell('Change', alignRight: true)),
              ],
            ),
          ),
          for (var i = 0; i < revenue.years.length; i++)
            _RevenueRow(
              year: revenue.years[i].year,
              isCurrent: revenue.years[i].year == now,
              revenueText: BandRevenue.formatCents(revenue.years[i].totalCents),
              change: revenue.yearOverYearChange(i),
            ),
          // Total footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color:
                CupertinoColors.secondarySystemBackground.resolveFrom(context),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text('Total',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                Expanded(
                  flex: 7,
                  child: Text(
                    BandRevenue.formatCents(revenue.totalCents),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {this.alignRight = false});
  final String text;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: CupertinoColors.secondaryLabel.resolveFrom(context),
      ),
    );
  }
}

class _RevenueRow extends StatelessWidget {
  const _RevenueRow({
    required this.year,
    required this.isCurrent,
    required this.revenueText,
    required this.change,
  });

  final int year;
  final bool isCurrent;
  final String revenueText;
  final double? change;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text('$year',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                if (isCurrent) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGreen
                          .resolveFrom(context)
                          .withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Current',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.systemGreen.resolveFrom(context),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              revenueText,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(flex: 3, child: _ChangeCell(change: change)),
        ],
      ),
    );
  }
}

class _ChangeCell extends StatelessWidget {
  const _ChangeCell({required this.change});
  final double? change;

  @override
  Widget build(BuildContext context) {
    if (change == null) {
      return Text(
        'N/A',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.tertiaryLabel.resolveFrom(context),
        ),
      );
    }
    final up = change! > 0;
    final flat = change! == 0;
    final color = flat
        ? CupertinoColors.secondaryLabel.resolveFrom(context)
        : (up
            ? CupertinoColors.systemGreen.resolveFrom(context)
            : CupertinoColors.systemRed.resolveFrom(context));
    final pct = change!.abs().toStringAsFixed(1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!flat)
          Icon(up ? CupertinoIcons.arrow_up : CupertinoIcons.arrow_down,
              size: 11, color: color),
        const SizedBox(width: 2),
        Text(
          flat ? '—' : '$pct%',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}
