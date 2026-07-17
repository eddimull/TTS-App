import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/eligible_booking.dart';
import '../providers/questionnaire_instances_provider.dart';

class SendQuestionnaireSheet extends ConsumerStatefulWidget {
  const SendQuestionnaireSheet({
    super.key,
    required this.bandId,
    required this.questionnaireId,
  });

  final int bandId;
  final int questionnaireId;

  @override
  ConsumerState<SendQuestionnaireSheet> createState() =>
      _SendQuestionnaireSheetState();
}

class _SendQuestionnaireSheetState
    extends ConsumerState<SendQuestionnaireSheet> {
  EligibleBooking? _booking;
  EligibleContact? _contact;
  bool _sending = false;
  String? _error;

  ({int bandId, int questionnaireId}) get _key =>
      (bandId: widget.bandId, questionnaireId: widget.questionnaireId);

  Future<void> _submit() async {
    final booking = _booking;
    final contact = _contact;
    if (booking == null || contact == null) {
      setState(() => _error = 'Choose a booking and a recipient.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(questionnaireInstancesProvider(_key).notifier).send(
            bookingId: booking.id,
            recipientContactId: contact.id,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Failed to send. Please try again.';
        });
      }
    }
  }

  Future<void> _pickBooking(List<EligibleBooking> bookings) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Choose booking'),
        actions: [
          for (final b in bookings)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                setState(() {
                  _booking = b;
                  _contact = null;
                });
              },
              child: Text(
                '${b.name}${b.date != null ? ' · ${b.date}' : ''}'
                '${b.alreadySent ? ' (already sent)' : ''}',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickContact(EligibleBooking booking) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Send to'),
        message: booking.contacts.any((c) => !c.canLogin)
            ? const Text(
                'Contacts without portal access can\'t be sent a questionnaire.')
            : null,
        actions: [
          for (final c in booking.contacts.where((c) => c.canLogin))
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                setState(() => _contact = c);
              },
              child: Text('${c.name}${c.isPrimary ? ' (primary)' : ''}'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(eligibleBookingsProvider(_key));
    final bookings = bookingsAsync.value ?? const <EligibleBooking>[];
    final selectedBooking = _booking;
    final portalContacts =
        selectedBooking?.contacts.where((c) => c.canLogin).toList() ??
            const <EligibleContact>[];

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed:
                        _sending ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Text('Send Questionnaire',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _sending ? null : _submit,
                    child: _sending
                        ? const CupertinoActivityIndicator()
                        : const Text('Send'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (bookingsAsync.isLoading && bookings.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CupertinoActivityIndicator()),
                )
              else if (bookingsAsync.hasError && bookings.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Failed to load bookings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.secondaryText),
                  ),
                )
              else if (bookings.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No upcoming bookings to send to.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.secondaryText),
                  ),
                )
              else ...[
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _sending ? null : () => _pickBooking(bookings),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Booking'),
                      Flexible(
                        child: Text(
                          selectedBooking?.name ?? 'Choose…',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.secondaryText),
                        ),
                      ),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _sending || selectedBooking == null
                      ? null
                      : () => _pickContact(selectedBooking),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Recipient'),
                      Flexible(
                        child: Text(
                          _contact?.name ??
                              (selectedBooking == null
                                  ? 'Choose a booking first'
                                  : portalContacts.isEmpty
                                      ? 'No portal-enabled contacts'
                                      : 'Choose…'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.secondaryText),
                        ),
                      ),
                    ],
                  ),
                ),
                if (selectedBooking != null && selectedBooking.alreadySent)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'This booking has already been sent this questionnaire.',
                      style: TextStyle(
                          color: context.secondaryText, fontSize: 13),
                    ),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                      color: CupertinoColors.destructiveRed, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
