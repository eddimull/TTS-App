import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

import '../data/models/booking_detail.dart';
import '../data/models/deposit.dart';

final _currency = NumberFormat.currency(symbol: r'$');

String _formatDate(String iso) {
  final date = DateTime.tryParse(iso);
  return date == null ? iso : DateFormat('MMM d, yyyy').format(date);
}

/// A label/value row with a smaller status line under the value.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBold = false,
    this.status,
    this.statusColor,
    this.statusBold = false,
    this.statusIcon = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;
  final String? status;
  final Color? statusColor;
  final bool statusBold;
  final bool statusIcon;

  @override
  Widget build(BuildContext context) {
    final color = statusColor ?? context.secondaryText;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 15)),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: valueColor,
                  fontWeight: valueBold ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (statusIcon) ...[
                  Icon(CupertinoIcons.exclamationmark_circle,
                      size: 14, color: color),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    status!,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight: statusBold ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The deposit line of a booking's finance summary: what the deposit is, and
/// where it stands. Renders nothing when there's no deposit to collect: no
/// price, a deposit of zero, or a booking with no contract.
class DepositFinanceRow extends StatelessWidget {
  const DepositFinanceRow({super.key, required this.booking});

  final BookingDetail booking;

  @override
  Widget build(BuildContext context) {
    final amount = double.parse(Deposit.resolve(booking).depositAmount);
    final state = booking.paymentDue;
    if (amount <= 0) return const SizedBox.shrink();
    if (state == null && booking.contractOption == 'none') {
      return const SizedBox.shrink();
    }

    final label = Deposit.label(booking);
    final value = _currency.format(amount);

    if (state == null) {
      // Not contracted yet, so nothing is due. A cancelled booking or a signed
      // but unconfirmed one will never get this date, so say nothing there.
      final awaitingSignature = booking.status != 'cancelled' &&
          booking.contract?.status != 'completed';
      return _StatusRow(
        label: label,
        value: value,
        status: awaitingSignature ? 'Due 3 weeks after signing' : null,
      );
    }

    final deposit = state.deposit;
    if (deposit.owedAmount <= 0) {
      return _StatusRow(
        label: label,
        value: value,
        status: 'Deposit paid',
        statusColor: CupertinoColors.systemGreen.resolveFrom(context),
      );
    }

    final owed = _currency.format(deposit.owedAmount);
    if (deposit.isOverdue) {
      return _StatusRow(
        label: label,
        value: value,
        status: '$owed overdue since ${_formatDate(deposit.overdueSince ?? deposit.dueDate)}',
        statusColor: CupertinoColors.systemRed.resolveFrom(context),
        statusBold: true,
        statusIcon: true,
      );
    }
    return _StatusRow(
      label: label,
      value: value,
      status: '$owed still due by ${_formatDate(deposit.dueDate)}',
    );
  }
}

/// The "Balance due" line of a booking's finance summary, with when it's due.
/// Red only once it's overdue, which is after the performance.
class BalanceFinanceRow extends StatelessWidget {
  const BalanceFinanceRow({super.key, required this.booking});

  final BookingDetail booking;

  @override
  Widget build(BuildContext context) {
    const label = 'Balance due';
    final value = booking.displayAmountDue;
    if (booking.isPaid) {
      return _StatusRow(
        label: label,
        value: value,
        valueColor: CupertinoColors.systemGreen.resolveFrom(context),
      );
    }

    final state = booking.paymentDue;
    if (state == null || state.balance.owedAmount <= 0) {
      return _StatusRow(label: label, value: value);
    }

    final balance = state.balance;
    if (balance.isOverdue) {
      final red = CupertinoColors.systemRed.resolveFrom(context);
      return _StatusRow(
        label: label,
        value: value,
        valueColor: red,
        valueBold: true,
        status: 'Overdue since the ${_formatDate(balance.overdueSince ?? state.eventDate)} show',
        statusColor: red,
        statusBold: true,
        statusIcon: true,
      );
    }
    if (balance.isDueNow) {
      final orange = CupertinoColors.systemOrange.resolveFrom(context);
      return _StatusRow(
        label: label,
        value: value,
        valueColor: orange,
        valueBold: true,
        status: 'Due now, show is ${_formatDate(state.eventDate)}',
        statusColor: orange,
        statusBold: true,
      );
    }
    final prefix = state.deposit.owedAmount > 0 ? 'Rest due' : 'Due';
    return _StatusRow(
      label: label,
      value: value,
      status: '$prefix by ${_formatDate(balance.dueDate)}',
    );
  }
}
