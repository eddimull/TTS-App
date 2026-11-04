import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../../../bookings/data/models/deposit.dart';
import '../../data/models/payments_due.dart';
import '../../providers/finances_provider.dart';

final _wholeDollars = NumberFormat.currency(symbol: r'$', decimalDigits: 0);
final _cents = NumberFormat.currency(symbol: r'$');

/// Whole dollars when the amount is whole, so a list scans quickly.
String _money(double amount) =>
    amount == amount.roundToDouble() ? _wholeDollars.format(amount) : _cents.format(amount);

/// "Nov 9" this year, "Jan 9, 2027" otherwise.
String _shortDate(String iso) {
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  return date.year == clock.now().year
      ? DateFormat('MMM d').format(date)
      : DateFormat('MMM d, yyyy').format(date);
}

String _countLabel(int count) => '$count ${count == 1 ? 'payment' : 'payments'}';

/// The Due tab: every payment still owed, one row each, most urgent first.
class PaymentsDueView extends ConsumerStatefulWidget {
  const PaymentsDueView({super.key, required this.bandId});

  final int bandId;

  @override
  ConsumerState<PaymentsDueView> createState() => _PaymentsDueViewState();
}

class _PaymentsDueViewState extends ConsumerState<PaymentsDueView> {
  bool _showLater = false;
  bool _showOlder = false;

  @override
  Widget build(BuildContext context) {
    return ref.watch(paymentsDueProvider(widget.bandId)).when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CupertinoActivityIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            child: ErrorView(
              message: ErrorView.friendlyMessage(e),
              onRetry: () =>
                  ref.read(paymentsDueProvider(widget.bandId).notifier).refresh(),
            ),
          ),
          data: (due) {
            if (due.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No payments due. Every contracted booking is paid in full.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.secondaryText),
                    ),
                  ),
                ),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _Tiles(due: due),
                  if (!due.overdue.isEmpty)
                    _Section(
                      title: 'OVERDUE',
                      titleColor: CupertinoColors.systemRed.resolveFrom(context),
                      total: due.overdue.total,
                      children: [for (final p in due.overdue.payments) _PaymentRow(payment: p)],
                    ),
                  if (!due.next30.isEmpty)
                    _Section(
                      title: 'NEXT 30 DAYS',
                      total: due.next30.total,
                      children: [for (final p in due.next30.payments) _PaymentRow(payment: p)],
                    ),
                  if (!due.later.isEmpty)
                    _Section(
                      title: 'LATER',
                      total: due.later.total,
                      children: _showLater
                          ? [for (final p in due.later.payments) _PaymentRow(payment: p)]
                          : [
                              _ShowAllRow(
                                title: _countLabel(due.later.count),
                                subtitle: 'Next: ${_shortDate(due.later.payments.first.dueDate)}',
                                total: due.later.total,
                                onTap: () => setState(() => _showLater = true),
                              ),
                            ],
                    ),
                  if (!due.older.isEmpty)
                    _Section(
                      title: 'OLDER',
                      total: due.older.total,
                      children: _showOlder
                          ? [for (final p in due.older.payments) _PaymentRow(payment: p)]
                          : [
                              _ShowAllRow(
                                title: _countLabel(due.older.count),
                                subtitle: 'Shows over 90 days ago',
                                total: due.older.total,
                                onTap: () => setState(() => _showOlder = true),
                              ),
                            ],
                    ),
                ]),
              ),
            );
          },
        );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.due});

  final PaymentsDue due;

  @override
  Widget build(BuildContext context) {
    final caughtUp = due.overdue.isEmpty;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Tile(
              title: 'Overdue',
              titleColor: caughtUp
                  ? CupertinoColors.systemGreen.resolveFrom(context)
                  : CupertinoColors.systemRed.resolveFrom(context),
              amount: due.overdue.total,
              caption: caughtUp ? 'All caught up' : _countLabel(due.overdue.count),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Tile(
              title: 'Next 30 days',
              titleColor: context.secondaryText,
              amount: due.next30.total,
              caption: _countLabel(due.next30.count),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.titleColor,
    required this.amount,
    required this.caption,
  });

  final String title;
  final Color titleColor;
  final double amount;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: titleColor)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_money(amount),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          Text(caption,
              style: TextStyle(fontSize: 13, color: context.secondaryText)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.total,
    required this.children,
    this.titleColor,
  });

  final String title;
  final Color? titleColor;
  final double total;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: titleColor ?? context.secondaryText,
                  ),
                ),
                Text(_money(total),
                    style: TextStyle(fontSize: 13, color: context.secondaryText)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      Container(
                        height: 0.5,
                        color: CupertinoColors.separator.resolveFrom(context),
                      ),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.semanticLabel,
    required this.title,
    required this.trailing,
    required this.subtitle,
    required this.detail,
    required this.onTap,
    this.detailColor,
    this.detailBold = false,
    this.chevron = true,
  });

  final String semanticLabel;
  final String title;
  final String trailing;
  final String subtitle;
  final String detail;
  final Color? detailColor;
  final bool detailBold;
  final bool chevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(trailing,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13, color: context.secondaryText),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            detail,
                            style: TextStyle(
                              fontSize: 13,
                              color: detailColor ?? context.secondaryText,
                              fontWeight:
                                  detailBold ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (chevron) ...[
                  const SizedBox(width: 10),
                  Icon(CupertinoIcons.chevron_right,
                      size: 14, color: context.tertiaryText),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final DuePayment payment;

  String get _kind => payment.isDeposit
      ? Deposit.labelFor(payment.depositType, payment.depositValue)
      : 'Balance';

  String get _subtitle {
    final kind = _kind;
    if (payment.isOverdue) {
      return payment.isDeposit
          ? '$kind · was due ${_shortDate(payment.dueDate)}'
          : '$kind · show was ${_shortDate(payment.eventDate)}';
    }
    if (payment.isDueNow && !payment.isDeposit) {
      return '$kind · show is ${_shortDate(payment.eventDate)}';
    }
    if (payment.isDeposit && payment.amountPaid > 0) {
      return '$kind · ${_money(payment.amountPaid)} of ${_money(payment.depositAmount)} paid';
    }
    return kind;
  }

  String get _detail {
    if (payment.isOverdue) {
      final days = payment.daysLate ?? 0;
      return '$days ${days == 1 ? 'day' : 'days'} late';
    }
    return payment.isDueNow ? 'Due now' : _shortDate(payment.dueDate);
  }

  @override
  Widget build(BuildContext context) {
    final detailColor = payment.isOverdue
        ? CupertinoColors.systemRed.resolveFrom(context)
        : payment.isDueNow
            ? CupertinoColors.systemOrange.resolveFrom(context)
            : null;
    return _RowShell(
      semanticLabel:
          '${payment.bookingName}, ${_money(payment.amount)}, $_subtitle, $_detail',
      title: payment.bookingName,
      trailing: _money(payment.amount),
      subtitle: _subtitle,
      detail: _detail,
      detailColor: detailColor,
      detailBold: detailColor != null,
      onTap: () => context
          .push('/bookings/${payment.bandId}/${payment.bookingId}/payments'),
    );
  }
}

class _ShowAllRow extends StatelessWidget {
  const _ShowAllRow({
    required this.title,
    required this.subtitle,
    required this.total,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      semanticLabel: 'Show all $title, ${_money(total)}, $subtitle',
      title: title,
      trailing: _money(total),
      subtitle: subtitle,
      detail: 'Show all',
      detailColor: CupertinoColors.systemBlue.resolveFrom(context),
      detailBold: true,
      chevron: false,
      onTap: onTap,
    );
  }
}
