import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/bookings_repository.dart';
import '../data/models/booking_payment.dart';
import '../providers/bookings_provider.dart';
import '../widgets/payment_type_picker.dart';

class BookingPaymentsScreen extends ConsumerWidget {
  const BookingPaymentsScreen({
    super.key,
    required this.bandId,
    required this.bookingId,
  });

  final int bandId;
  final int bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(bookingDetailProvider(
        (bandId: bandId, bookingId: bookingId)));

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Payments'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _showRecordPayment(context, ref),
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      child: SafeArea(
        child: detailAsync.when(
          loading: () =>
              const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (booking) {
            return CustomScrollView(
              slivers: [
                // ── Financial summary card ──────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: CupertinoColors.tertiarySystemBackground
                            .resolveFrom(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _FinRow(
                              label: 'Total',
                              value: booking.displayPrice,
                              bold: true),
                          const SizedBox(height: 6),
                          _FinRow(
                            label: 'Paid',
                            value: booking.displayAmountPaid,
                            valueColor: CupertinoColors.systemGreen
                                .resolveFrom(context),
                          ),
                          const SizedBox(height: 6),
                          _FinRow(
                            label: 'Balance due',
                            value: booking.displayAmountDue,
                            valueColor: booking.isPaid
                                ? CupertinoColors.systemGreen
                                    .resolveFrom(context)
                                : CupertinoColors.systemRed
                                    .resolveFrom(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Payments list ───────────────────────────────────────
                if (booking.payments.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'No payments recorded yet.',
                        style: TextStyle(
                            color: CupertinoColors.secondaryLabel),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _PaymentRow(
                        payment: booking.payments[i],
                        onDelete: () => _confirmDelete(
                          context,
                          ref,
                          booking.payments[i],
                        ),
                      ),
                      childCount: booking.payments.length,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _invalidate(WidgetRef ref) {
    ref.invalidate(bookingDetailProvider(
        (bandId: bandId, bookingId: bookingId)));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    BookingPayment payment,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete Payment'),
        content: Text(
            'Delete "${payment.name}" (${payment.displayAmount})?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final repo = ref.read(bookingsRepositoryProvider);
      await repo.deletePayment(bandId, bookingId, payment.id);
      _invalidate(ref);
    } catch (e) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showRecordPayment(BuildContext context, WidgetRef ref) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _RecordPaymentSheet(
        onSaved: () => _invalidate(ref),
        bandId: bandId,
        bookingId: bookingId,
      ),
    );
  }
}

class _FinRow extends StatelessWidget {
  const _FinRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 15,
                fontWeight:
                    bold ? FontWeight.w600 : FontWeight.normal)),
        Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight:
                    bold ? FontWeight.w600 : FontWeight.normal,
                color: valueColor)),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, required this.onDelete});

  final BookingPayment payment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                Row(
                  children: [
                    Text(
                      payment.displayPaymentType,
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context)),
                    ),
                    if (payment.date != null &&
                        payment.date!.isNotEmpty) ...[
                      Text(
                        '  ·  ${_formatDate(payment.date!)}',
                        style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Text(
            payment.displayAmount,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.systemGreen.resolveFrom(context),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
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

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }
}

// ── Record payment bottom sheet ───────────────────────────────────────────────

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({
    required this.onSaved,
    required this.bandId,
    required this.bookingId,
  });

  final VoidCallback onSaved;
  final int bandId;
  final int bookingId;

  @override
  ConsumerState<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  String _paymentType = 'cash';
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) => DateFormat('MMM d, yyyy').format(d);

  void _pickDate() {
    DateTime temp = _date;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: 300,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CupertinoButton(
                  onPressed: () {
                    setState(() => _date = temp);
                    Navigator.pop(context);
                  },
                  child: const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _date,
                onDateTimeChanged: (d) => temp = d,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickPaymentType() {
    String temp = _paymentType;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: 300,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CupertinoButton(
                  onPressed: () {
                    setState(() => _paymentType = temp);
                    Navigator.pop(context);
                  },
                  child: const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Expanded(
              child: PaymentTypePicker(
                selectedValue: _paymentType,
                onChanged: (v) => temp = v,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final amount = _amountCtrl.text.trim();
    if (name.isEmpty || amount.isEmpty) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(bookingsRepositoryProvider);
      await repo.addPayment(widget.bandId, widget.bookingId, {
        'name': name,
        'amount': amount,
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'payment_type': _paymentType,
      });
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  // Returns human label for selected payment type
  String get _paymentTypeLabel {
    return paymentTypes
        .where((t) => t.$1 == _paymentType)
        .map((t) => t.$2)
        .firstOrNull ?? 'Cash';
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
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey4.resolveFrom(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Record Payment',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                  if (_saving)
                    const CupertinoActivityIndicator()
                  else
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _save,
                      child: const Text('Save',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _nameCtrl,
                placeholder: 'Payment name (e.g. Deposit)',
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _amountCtrl,
                placeholder: 'Amount (e.g. 500.00)',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(r'$'),
                ),
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 8),
              // Date row
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: CupertinoColors.systemGrey4
                          .resolveFrom(context),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Date',
                          style: TextStyle(
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context))),
                      Text(_formatDate(_date)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Payment type row
              GestureDetector(
                onTap: _pickPaymentType,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: CupertinoColors.systemGrey4
                          .resolveFrom(context),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Payment Type',
                          style: TextStyle(
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context))),
                      Row(
                        children: [
                          Text(_paymentTypeLabel),
                          const SizedBox(width: 4),
                          Icon(CupertinoIcons.chevron_right,
                              size: 14,
                              color: CupertinoColors.tertiaryLabel
                                  .resolveFrom(context)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
