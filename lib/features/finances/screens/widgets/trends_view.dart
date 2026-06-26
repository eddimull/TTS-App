import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../../data/models/finance_trends.dart';
import '../../providers/finances_provider.dart';
import 'trends_chart.dart';
import 'trends_count_row.dart';

final _money = NumberFormat.currency(symbol: '\$');
String _fmtCents(int cents) => _money.format(cents / 100.0);

/// Trends tab body (sliver). Holds year/snapshot/compare state locally and
/// drives trendsProvider.
class TrendsView extends ConsumerStatefulWidget {
  const TrendsView({super.key, required this.bandId});

  final int bandId;

  @override
  ConsumerState<TrendsView> createState() => _TrendsViewState();
}

class _TrendsViewState extends ConsumerState<TrendsView> {
  int _year = DateTime.now().year;
  String? _snapshotDate; // YYYY-MM-DD
  bool _compare = false;

  // Last successfully loaded data, kept on screen while a new year loads so the
  // chart doesn't flash a spinner when the year changes.
  FinanceTrends? _lastTrends;

  TrendsParams get _params => TrendsParams(
        bandId: widget.bandId,
        year: _year,
        snapshotDate: _snapshotDate,
        compareWithCurrent: _compare,
      );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(trendsProvider(_params));

    // Remember the latest good data so a year change reloads underneath the
    // existing chart instead of flashing a spinner.
    final fresh = async.hasValue ? async.value : null;
    if (fresh != null) _lastTrends = fresh;
    final trends = _lastTrends;
    // True while a refetch is in flight but we still have a prior chart to show
    // (e.g. just flicked to a new year) — drives the over-chart loading veil.
    final reloading = async.isLoading && trends != null;

    // First ever load (no data yet) shows a spinner; an error with no prior
    // data shows the error view. Otherwise we keep the last chart on screen.
    if (trends == null) {
      if (async.hasError) {
        return SliverFillRemaining(
          child: ErrorView(
            message: ErrorView.friendlyMessage(async.error!),
            onRetry: () => ref.read(trendsProvider(_params).notifier).refresh(),
          ),
        );
      }
      return const SliverFillRemaining(
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    return SliverList(
      delegate: SliverChildListDelegate([
        const SizedBox(height: 8),
        _ControlsRow(
          year: _year,
          availableYears: trends.availableYears,
          snapshotDate: _snapshotDate,
          compare: _compare,
          onYear: (y) {
            if (mounted) setState(() => _year = y);
          },
          onPickDate: _pickSnapshot,
          onClearDate: () {
            if (mounted) {
              setState(() {
                _snapshotDate = null;
                _compare = false;
              });
            }
          },
          onToggleCompare: (v) {
            if (mounted) setState(() => _compare = v);
          },
        ),
        const SizedBox(height: 8),
        if (_isFullyEmpty(trends))
          _EmptyBody(year: _year, snapshotDate: _snapshotDate)
        else ...[
          // Flick the chart horizontally to change year (left → later year,
          // right → earlier). The old chart stays visible while the new year
          // loads, so there's no spinner flash.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -250) {
                _goToYear(_nextYear(1, trends.availableYears)); // left → later
              } else if (v > 250) {
                _goToYear(_nextYear(-1, trends.availableYears)); // right → earlier
              }
            },
            child: Stack(
              children: [
                Column(
                  children: [
                    TrendsChart(trends: trends),
                    TrendsCountRow(trends: trends),
                  ],
                ),
                // Loading veil over the chart while a new year is fetched, so a
                // flick visibly registers even when the prior chart stays up.
                if (reloading)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemBackground
                            .resolveFrom(context)
                            .withValues(alpha: 0.45),
                      ),
                      child: const Center(child: CupertinoActivityIndicator()),
                    ),
                  ),
              ],
            ),
          ),
          const _Legend(),
          const SizedBox(height: 12),
          _SummaryCards(trends: trends),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }

  /// Resolves the focused year after a drag/flick. [delta] is +1 for a later
  /// year, -1 for earlier. Returns null if there's no year to move to (at an
  /// edge of the available range), so the chart should spring back.
  int? _nextYear(int delta, List<int> availableYears) {
    if (availableYears.contains(_year)) {
      // availableYears is newest-first, so a later year is a lower index.
      final nextIdx = availableYears.indexOf(_year) - delta;
      if (nextIdx < 0 || nextIdx >= availableYears.length) return null;
      return availableYears[nextIdx];
    }
    return _year + delta;
  }

  /// Commits a year change from a flick. No-op when [year] is null (already at
  /// the edge of the available range). The old chart stays via _lastTrends
  /// while the new year loads.
  void _goToYear(int? year) {
    if (year != null && year != _year && mounted) {
      setState(() => _year = year);
    }
  }

  /// Empty only when there's nothing to show at all. When comparing, the
  /// current series (and its delta cards) still carry the time-travel insight
  /// even if the snapshot series is sparse, so don't blank the view then.
  bool _isFullyEmpty(FinanceTrends trends) {
    if (!trends.isEmpty) return false;
    if (trends.comparing) {
      final current = trends.currentMonths;
      final currentEmpty = current == null || current.every((m) => m.isZero);
      return currentEmpty;
    }
    return true;
  }

  Future<void> _pickSnapshot() async {
    final now = DateTime.now();
    // Date-only "today" so it's always within maximumDate (which is end of
    // today). Using DateTime.now() for both initial and max can make the
    // picker clamp/reset on the first selection.
    final today = DateTime(now.year, now.month, now.day);
    DateTime temp =
        _snapshotDate != null ? DateTime.parse(_snapshotDate!) : today;
    final picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => Container(
        height: 300,
        color: CupertinoColors.systemBackground.resolveFrom(sheetContext),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CupertinoButton(
                  // Pop the SHEET's route (sheetContext), returning the chosen
                  // date — popping the State's context would dismiss the whole
                  // Finances page back to "More".
                  onPressed: () => Navigator.of(sheetContext)
                      .pop(DateFormat('yyyy-MM-dd').format(temp)),
                  child: const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: temp,
                maximumDate: DateTime(now.year, now.month, now.day, 23, 59, 59),
                onDateTimeChanged: (d) => temp = d,
              ),
            ),
          ],
        ),
      ),
    );

    // picked is null if the sheet was dismissed without tapping Done.
    if (picked != null && mounted) {
      setState(() {
        _snapshotDate = picked;
        // True time travel: viewing the snapshot alone often looks empty
        // (little existed then), so default to the snapshot-vs-current
        // comparison — that's the insight.
        _compare = true;
      });
    }
  }
}

// ── Controls ──────────────────────────────────────────────────────────────────

class _ControlsRow extends StatelessWidget {
  const _ControlsRow({
    required this.year,
    required this.availableYears,
    required this.snapshotDate,
    required this.compare,
    required this.onYear,
    required this.onPickDate,
    required this.onClearDate,
    required this.onToggleCompare,
  });

  final int year;
  final List<int> availableYears;
  final String? snapshotDate;
  final bool compare;
  final void Function(int) onYear;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  final void Function(bool) onToggleCompare;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final tint = CupertinoColors.systemBlue.resolveFrom(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _showYearPicker(context),
                child: _Pill(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('$year',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: label)),
                    const SizedBox(width: 2),
                    Icon(CupertinoIcons.chevron_down, size: 12, color: label),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: GestureDetector(
                  onTap: onPickDate,
                  child: _Pill(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(CupertinoIcons.clock, size: 13, color: tint),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          snapshotDate == null
                              ? 'All time'
                              : 'As of ${DateFormat('MMM d, yyyy').format(DateTime.parse(snapshotDate!))}',
                          style: TextStyle(fontSize: 13, color: label),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (snapshotDate != null) ...[
                        const SizedBox(width: 2),
                        Semantics(
                          button: true,
                          label: 'Clear snapshot date',
                          child: GestureDetector(
                            onTap: onClearDate,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(CupertinoIcons.clear_circled_solid,
                                  size: 14,
                                  color: CupertinoColors.tertiaryLabel
                                      .resolveFrom(context)),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ],
          ),
          if (snapshotDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text('Compare with current',
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context))),
                  const SizedBox(width: 8),
                  CupertinoSwitch(value: compare, onChanged: onToggleCompare),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showYearPicker(BuildContext context) {
    final years = availableYears.isNotEmpty ? availableYears : [year];
    final foundIndex = years.indexOf(year);
    final initial = foundIndex < 0 ? 0 : foundIndex;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: 250,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: CupertinoPicker(
          itemExtent: 36,
          scrollController: FixedExtentScrollController(initialItem: initial),
          onSelectedItemChanged: (i) => onYear(years[i]),
          children: [for (final y in years) Center(child: Text('$y'))],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: CupertinoColors.separator.resolveFrom(context), width: 0.5),
      ),
      child: child,
    );
  }
}

// ── Legend ────────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String label) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context))),
        ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(spacing: 14, runSpacing: 6, children: [
        item(CupertinoColors.systemBlue.resolveFrom(context), 'Paid'),
        item(CupertinoColors.systemGrey.resolveFrom(context), 'Unpaid'),
        item(CupertinoColors.systemGreen.resolveFrom(context), 'Forecast'),
        item(CupertinoColors.systemPurple.resolveFrom(context), 'Band cut'),
      ]),
    );
  }
}

// ── Summary cards ─────────────────────────────────────────────────────────────

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.trends});
  final FinanceTrends trends;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: _StatCard(
                label: 'Paid',
                value: _fmtCents(trends.totalPaidCents),
                tint: CupertinoColors.systemBlue.resolveFrom(context),
                deltaCents: trends.deltaPaidCents,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Outstanding',
                value: _fmtCents(trends.totalUnpaidCents),
                tint: CupertinoColors.systemGrey.resolveFrom(context),
                deltaCents: trends.deltaUnpaidCents,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _StatCard(
                label: 'Band cut',
                value: _fmtCents(trends.totalNetCents),
                tint: CupertinoColors.systemPurple.resolveFrom(context),
                deltaCents: trends.deltaNetCents,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Bookings',
                value: '${trends.totalCount}',
                tint: CupertinoColors.systemOrange.resolveFrom(context),
                deltaCount: trends.deltaCount,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _StatCard(
                label: 'Forecast',
                value: _fmtCents(trends.totalForecastCents),
                tint: CupertinoColors.systemGreen.resolveFrom(context),
                deltaCents: trends.deltaForecastCents,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.tint,
    this.deltaCents,
    this.deltaCount,
  });

  final String label;
  final String value;
  final Color tint;
  final int? deltaCents;
  final int? deltaCount;

  @override
  Widget build(BuildContext context) {
    final delta = deltaCents ?? deltaCount;
    final isMoney = deltaCents != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context))),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: tint)),
          if (delta != null && delta != 0) ...[
            const SizedBox(height: 2),
            _DeltaBadge(delta: delta, isMoney: isMoney),
          ],
        ],
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.delta, required this.isMoney});
  final int delta;
  final bool isMoney;

  @override
  Widget build(BuildContext context) {
    final up = delta > 0;
    final color = up
        ? CupertinoColors.systemGreen.resolveFrom(context)
        : CupertinoColors.systemRed.resolveFrom(context);
    final text = isMoney ? _fmtCents(delta.abs()) : '${delta.abs()}';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(up ? CupertinoIcons.arrow_up : CupertinoIcons.arrow_down,
          size: 11, color: color),
      const SizedBox(width: 2),
      Flexible(
        child: Text('$text vs snapshot',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: color),
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}

// ── Empty ─────────────────────────────────────────────────────────────────────

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.year, required this.snapshotDate});
  final int year;
  final String? snapshotDate;

  @override
  Widget build(BuildContext context) {
    final hasSnapshot = snapshotDate != null;
    final asOf = hasSnapshot
        ? DateFormat('MMM d, yyyy').format(DateTime.parse(snapshotDate!))
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: EmptyStateView(
        icon: CupertinoIcons.chart_bar,
        title: hasSnapshot
            ? 'Nothing booked for $year as of $asOf'
            : 'No activity in $year',
        subtitle: hasSnapshot
            ? 'Those bookings were created after $asOf. Clear the date or pick a later one.'
            : 'Try another year or set a snapshot date.',
      ),
    );
  }
}
