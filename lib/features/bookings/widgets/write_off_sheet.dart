import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../data/models/booking_detail.dart';
import '../data/bookings_repository.dart';

final _currency = NumberFormat.currency(symbol: r'$');

/// Bottom sheet that writes off what's left of a booking's balance. Silent by
/// default: the client hears about it only if "Notify client" is switched on.
class WriteOffSheet extends ConsumerStatefulWidget {
  const WriteOffSheet({
    super.key,
    required this.bandId,
    required this.booking,
    required this.onSaved,
  });

  final int bandId;
  final BookingDetail booking;
  final VoidCallback onSaved;

  @override
  ConsumerState<WriteOffSheet> createState() => _WriteOffSheetState();
}

class _WriteOffSheetState extends ConsumerState<WriteOffSheet> {
  final _noteCtrl = TextEditingController();
  bool _notifyClient = false;
  bool _saving = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  String get _owed =>
      _currency.format(double.tryParse(widget.booking.amountDue ?? '') ?? 0);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(bookingsRepositoryProvider).writeOffBalance(
            widget.bandId,
            widget.booking.id,
            notifyClient: _notifyClient,
            note: _noteCtrl.text,
          );
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Couldn’t Write Off'),
          content: Text(ErrorView.friendlyMessage(e)),
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

  @override
  Widget build(BuildContext context) {
    final secondary = context.secondaryText;
    return Container(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SafeArea(
        top: false,
        // Scrolls once the keyboard leaves too little room (landscape, large
        // text), so the Write Off button stays reachable.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Text(
                'Write Off $_owed',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Marks the booking settled without recording a payment. '
                'Amount paid stays ${widget.booking.displayAmountPaid}.',
                style: TextStyle(fontSize: 13, color: secondary),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _noteCtrl,
                placeholder: 'Note (optional)',
                maxLength: 255,
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 12),
              // Merged so screen readers announce the switch as "Notify client".
              MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Notify client',
                              style: TextStyle(fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                            _notifyClient
                                ? 'Emails the contacts that nothing more is owed.'
                                : 'The client isn’t told. Their portal shows nothing due.',
                            style: TextStyle(fontSize: 13, color: secondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    CupertinoSwitch(
                      value: _notifyClient,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _notifyClient = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              CupertinoButton.filled(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CupertinoActivityIndicator(
                        color: CupertinoColors.white)
                    : const Text('Write Off'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
