import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bookings/data/models/booking_contact.dart';
import '../../bookings/providers/bookings_provider.dart';
import '../data/models/eligible_booking.dart';
import '../providers/questionnaire_instances_provider.dart';
import 'send_from_booking_sheet.dart';

/// Booking contacts a questionnaire can go to: those linked to a contact
/// record (the send endpoint addresses contacts by that id).
List<EligibleContact> eligibleContactsFrom(List<BookingContact> contacts) => [
      for (final c in contacts)
        if (c.contactId != null)
          EligibleContact(
            id: c.contactId!,
            name: c.name,
            isPrimary: c.isPrimary,
            canLogin: c.canLogin,
          ),
    ];

/// Opens the booking's send-questionnaire sheet from an event, loading the
/// booking's templates and contacts first. The sheet refreshes the booking's
/// questionnaires on send, which the event's Notes tab watches.
Future<void> sendQuestionnaireFromEvent(
  BuildContext context, {
  required int bandId,
  required int bookingId,
}) async {
  final container = ProviderScope.containerOf(context);
  final key = (bandId: bandId, bookingId: bookingId);

  BookingQuestionnaires questionnaires;
  List<EligibleContact> contacts;
  try {
    final questionnairesFuture =
        container.read(bookingQuestionnairesProvider(key).future);
    final booking = await container.read(bookingDetailProvider(key).future);
    questionnaires = await questionnairesFuture;
    contacts = eligibleContactsFrom(booking.contacts);
  } catch (_) {
    if (context.mounted) {
      await _alert(context, "Couldn't load questionnaires",
          'Check your connection and try again.');
    }
    return;
  }
  if (!context.mounted) return;

  if (questionnaires.availableQuestionnaires.isEmpty) {
    await _alert(context, 'No active questionnaires',
        'Create or activate a questionnaire for the band first.');
    return;
  }
  if (contacts.isEmpty) {
    await _alert(context, 'No one to send it to',
        'Add a contact to the booking first.');
    return;
  }

  await showCupertinoModalPopup<void>(
    context: context,
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: SendFromBookingSheet(
        bandId: bandId,
        bookingId: bookingId,
        templates: questionnaires.availableQuestionnaires,
        contacts: contacts,
      ),
    ),
  );
}

Future<void> _alert(BuildContext context, String title, String message) =>
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
