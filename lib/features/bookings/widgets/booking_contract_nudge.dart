import 'package:flutter/cupertino.dart';

import '../data/models/booking_detail.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// Contextual next-step card for the send-a-contract flow, shown at the top
/// of the booking detail screen.
///
/// A Bandmate-generated contract needs a contact before it can be sent, and
/// then needs to actually be sent — neither step is discoverable from the
/// detail screen's flat tile list, so this card walks the user through:
///
///   no contacts  → "Add a contact to send the contract"  → contacts screen
///   contacts, unsent contract → "…ready to send"          → contract screen
///
/// Nothing is rendered for bookings without a Bandmate contract
/// (contract_option 'none'/'external') or once the contract is sent or
/// completed. Dismissal is session-local.
class BookingContractNudge extends StatefulWidget {
  const BookingContractNudge({
    super.key,
    required this.booking,
    required this.onAddContact,
    required this.onSendContract,
  });

  final BookingDetail booking;
  final VoidCallback onAddContact;
  final VoidCallback onSendContract;

  @override
  State<BookingContractNudge> createState() => _BookingContractNudgeState();
}

class _BookingContractNudgeState extends State<BookingContractNudge> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final b = widget.booking;
    // Only the Bandmate-generated contract has a send flow.
    if (b.contractOption != 'default') return const SizedBox.shrink();
    // Contract statuses are pending → sent → completed; nudge only while
    // the contract still needs action (missing row counts as pending).
    final status = b.contract?.status;
    if (status == 'sent' || status == 'completed') {
      return const SizedBox.shrink();
    }

    final needsContact = b.contacts.isEmpty;
    final message = needsContact
        ? 'Add a contact to send the contract to.'
        : 'The contract is ready to send.';
    final actionLabel = needsContact ? 'Add contact' : 'Go to contract';
    final onAction = needsContact ? widget.onAddContact : widget.onSendContract;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: CupertinoColors.activeBlue
              .resolveFrom(context)
              .withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.doc_text,
              size: 20,
              color: CupertinoColors.activeBlue.resolveFrom(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      color: context.primaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: onAction,
                    child: Text(
                      actionLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'Dismiss',
              child: CupertinoButton(
                padding: const EdgeInsets.all(8),
                minimumSize: Size.zero,
                onPressed: () => setState(() => _dismissed = true),
                child: Icon(
                  CupertinoIcons.xmark,
                  size: 16,
                  color: context.tertiaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
