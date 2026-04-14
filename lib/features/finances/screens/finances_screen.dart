import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../../../shared/widgets/status_chip.dart';
import '../data/models/finance_booking.dart';
import '../providers/finances_provider.dart';

final _fmt = NumberFormat.currency(symbol: '\$');

enum _FinancesTab { unpaid, paid }

// ── Root screen ───────────────────────────────────────────────────────────────

class FinancesScreen extends ConsumerStatefulWidget {
  const FinancesScreen({super.key});

  @override
  ConsumerState<FinancesScreen> createState() => _FinancesScreenState();
}

class _FinancesScreenState extends ConsumerState<FinancesScreen> {
  _FinancesTab _tab = _FinancesTab.unpaid;

  @override
  Widget build(BuildContext context) {
    final bandAsync = ref.watch(selectedBandProvider);

    return bandAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Finances')),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Finances')),
        child: ErrorView(message: ErrorView.friendlyMessage(e)),
      ),
      data: (bandId) {
        if (bandId == null) {
          return const CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(middle: Text('Finances')),
            child: ErrorView(message: 'No band selected.'),
          );
        }
        return _FinancesBody(
          bandId: bandId,
          tab: _tab,
          onTabChanged: (t) => setState(() => _tab = t),
        );
      },
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _FinancesBody extends ConsumerStatefulWidget {
  const _FinancesBody({
    required this.bandId,
    required this.tab,
    required this.onTabChanged,
  });

  final int bandId;
  final _FinancesTab tab;
  final void Function(_FinancesTab) onTabChanged;

  @override
  ConsumerState<_FinancesBody> createState() => _FinancesBodyState();
}

class _FinancesBodyState extends ConsumerState<_FinancesBody> {
  int _selectedYear = DateTime.now().year;
  String _nameQuery = '';
  String? _statusFilter; // null = All

  static const int _minYear = 2000;
  static final int _maxYear = DateTime.now().year + 3;

  FinancesParams get _params =>
      FinancesParams(bandId: widget.bandId, year: _selectedYear);

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = widget.tab == _FinancesTab.unpaid
        ? ref.watch(unpaidServicesProvider(_params))
        : ref.watch(paidServicesProvider(_params));

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverRefreshControl(
            onRefresh: () => widget.tab == _FinancesTab.unpaid
                ? ref.read(unpaidServicesProvider(_params).notifier).refresh()
                : ref.read(paidServicesProvider(_params).notifier).refresh(),
          ),
          const CupertinoSliverNavigationBar(
            largeTitle: Text('Finances'),
          ),
          // ── Unpaid / Paid tab switcher ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: CupertinoSegmentedControl<_FinancesTab>(
                groupValue: widget.tab,
                onValueChanged: widget.onTabChanged,
                children: const {
                  _FinancesTab.unpaid: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text('Unpaid'),
                  ),
                  _FinancesTab.paid: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text('Paid'),
                  ),
                },
              ),
            ),
          ),
          // ── Year stepper ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    onPressed: _selectedYear > _minYear
                        ? () => setState(() => _selectedYear--)
                        : null,
                    child: Icon(
                      CupertinoIcons.chevron_left,
                      size: 18,
                      color: _selectedYear > _minYear
                          ? CupertinoColors.label.resolveFrom(context)
                          : CupertinoColors.tertiaryLabel.resolveFrom(context),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      _selectedYear.toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    onPressed: _selectedYear < _maxYear
                        ? () => setState(() => _selectedYear++)
                        : null,
                    child: Icon(
                      CupertinoIcons.chevron_right,
                      size: 18,
                      color: _selectedYear < _maxYear
                          ? CupertinoColors.label.resolveFrom(context)
                          : CupertinoColors.tertiaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Name search ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: CupertinoSearchTextField(
                placeholder: 'Search by name',
                onChanged: (q) => setState(() => _nameQuery = q),
              ),
            ),
          ),
          // ── Status filter pills ──
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [null, 'confirmed', 'pending', 'draft', 'cancelled']
                    .map((s) {
                  final isSelected = _statusFilter == s;
                  final label = switch (s) {
                    null => 'All',
                    'confirmed' => 'Confirmed',
                    'pending' => 'Pending',
                    'draft' => 'Draft',
                    'cancelled' => 'Cancelled',
                    _ => s,
                  };
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _statusFilter = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? CupertinoColors.systemBlue.resolveFrom(context)
                              : CupertinoColors.tertiarySystemBackground
                                  .resolveFrom(context),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? CupertinoColors.white
                                : CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          bookingsAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: ErrorView(
                message: ErrorView.friendlyMessage(e),
                onRetry: () => widget.tab == _FinancesTab.unpaid
                    ? ref.read(unpaidServicesProvider(_params).notifier).refresh()
                    : ref.read(paidServicesProvider(_params).notifier).refresh(),
              ),
            ),
            data: (bookings) {
              // Client-side filters
              var filtered = bookings;
              if (_nameQuery.isNotEmpty) {
                final q = _nameQuery.toLowerCase();
                filtered = filtered
                    .where((b) => b.name.toLowerCase().contains(q))
                    .toList();
              }
              if (_statusFilter != null) {
                filtered = filtered
                    .where((b) => b.status?.toLowerCase() == _statusFilter)
                    .toList();
              }

              if (filtered.isEmpty) {
                return SliverFillRemaining(
                  child: EmptyStateView(
                    icon: widget.tab == _FinancesTab.unpaid
                        ? CupertinoIcons.money_dollar_circle
                        : CupertinoIcons.checkmark_seal,
                    title: widget.tab == _FinancesTab.unpaid
                        ? 'No outstanding balances'
                        : 'No paid bookings',
                    subtitle: widget.tab == _FinancesTab.unpaid
                        ? 'All bookings are fully paid.'
                        : 'Paid bookings will appear here.',
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == 0) {
                      return _SummaryCard(bookings: filtered, tab: widget.tab);
                    }
                    final booking = filtered[index - 1];
                    return _FinanceCard(
                      booking: booking,
                      tab: widget.tab,
                      onTap: () => context.push(
                          '/bookings/${widget.bandId}/${booking.id}'),
                    );
                  },
                  childCount: filtered.length + 1,
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.bookings, required this.tab});

  final List<FinanceBooking> bookings;
  final _FinancesTab tab;

  @override
  Widget build(BuildContext context) {
    final totalPrice = bookings.fold<double>(
        0, (s, b) => s + (double.tryParse(b.price ?? '0') ?? 0));
    final totalPaid = bookings.fold<double>(
        0, (s, b) => s + (double.tryParse(b.amountPaid ?? '0') ?? 0));
    final totalDue = bookings.fold<double>(
        0, (s, b) => s + (double.tryParse(b.amountDue ?? '0') ?? 0));

    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(context);
    final redColor = CupertinoColors.systemRed.resolveFrom(context);
    final greenColor = CupertinoColors.systemGreen.resolveFrom(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Count row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tab == _FinancesTab.unpaid ? 'Unpaid services' : 'Paid services',
                style: TextStyle(fontSize: 13, color: secondaryLabel),
              ),
              Text(
                '${bookings.length} ${bookings.length == 1 ? 'booking' : 'bookings'}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: secondaryLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _Divider(),
          const SizedBox(height: 10),
          // Total value
          _SummaryRow(
            label: 'Total value',
            value: _fmt.format(totalPrice),
            valueColor: CupertinoColors.label.resolveFrom(context),
          ),
          const SizedBox(height: 6),
          // Amount paid
          _SummaryRow(
            label: 'Paid',
            value: _fmt.format(totalPaid),
            valueColor: greenColor,
          ),
          if (tab == _FinancesTab.unpaid) ...[
            const SizedBox(height: 6),
            _SummaryRow(
              label: 'Outstanding',
              value: _fmt.format(totalDue),
              valueColor: redColor,
              bold: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.valueColor,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
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

// ── Finance card ──────────────────────────────────────────────────────────────

class _FinanceCard extends StatelessWidget {
  const _FinanceCard({
    required this.booking,
    required this.tab,
    this.onTap,
  });

  final FinanceBooking booking;
  final _FinancesTab tab;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isUnpaid = tab == _FinancesTab.unpaid;
    final accentColor = isUnpaid
        ? CupertinoColors.systemRed.resolveFrom(context)
        : CupertinoColors.systemGreen.resolveFrom(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Full-height accent bar on the left
            Positioned(top: 0, bottom: 0, left: 0, child: Container(width: 3, color: accentColor)),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 11, 0, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + status chip
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              booking.name,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (booking.status != null &&
                              booking.status!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            StatusChip(status: booking.status!),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatDate(booking),
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                      if (booking.venueName != null &&
                          booking.venueName!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(CupertinoIcons.location,
                                size: 11,
                                color: CupertinoColors.tertiaryLabel
                                    .resolveFrom(context)),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                booking.venueName!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.secondaryLabel
                                      .resolveFrom(context),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      _PaymentBar(booking: booking),
                      const SizedBox(height: 5),
                      // Price · paid · due
                      Wrap(
                        spacing: 6,
                        children: [
                          Text(
                            booking.displayPrice,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          Text('·',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.tertiaryLabel
                                      .resolveFrom(context))),
                          Text(
                            '${booking.displayAmountPaid} paid',
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
                            ),
                          ),
                          if (isUnpaid) ...[
                            Text('·',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: CupertinoColors.tertiaryLabel
                                        .resolveFrom(context))),
                            Text(
                              '${booking.displayAmountDue} due',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: accentColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
          ],
        ),
      ),
    );
  }

  String _formatDate(FinanceBooking booking) {
    final dateStr = DateFormat('EEE, MMM d, yyyy').format(booking.parsedDate);
    if (booking.startTime != null && booking.startTime!.isNotEmpty) {
      return '$dateStr at ${toAmPm(booking.startTime!)}';
    }
    return dateStr;
  }
}

// ── Payment progress bar ──────────────────────────────────────────────────────

class _PaymentBar extends StatelessWidget {
  const _PaymentBar({required this.booking});

  final FinanceBooking booking;

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(booking.price ?? '0') ?? 0;
    final paid = double.tryParse(booking.amountPaid ?? '0') ?? 0;
    final fraction = price > 0 ? (paid / price).clamp(0.0, 1.0) : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final paidWidth = totalWidth * fraction;

        return ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                // Background (unpaid portion)
                Container(
                  width: totalWidth,
                  color: CupertinoColors.systemFill.resolveFrom(context),
                ),
                // Paid portion
                Container(
                  width: paidWidth,
                  color: fraction >= 1.0
                      ? CupertinoColors.systemGreen.resolveFrom(context)
                      : CupertinoColors.systemOrange.resolveFrom(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
