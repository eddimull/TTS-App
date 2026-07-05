import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contact.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contract.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/widgets/booking_contract_nudge.dart';

// Guides the user through the send-a-contract flow from the booking detail
// screen: a booking with a Bandmate-generated contract that still needs
// contacts prompts "add a contact"; once contacts exist and the contract is
// still unsent, it prompts "send". Sent/completed contracts, external
// uploads, and no-contract bookings show nothing.

BookingDetail _booking({
  String? contractOption = 'default',
  String? contractStatus = 'pending',
  bool withContact = false,
}) {
  return BookingDetail(
    id: 42,
    name: 'Summer Festival',
    startDate: '2026-08-01',
    endDate: '2026-08-01',
    eventCount: 1,
    isMultiEvent: false,
    isPaid: false,
    status: 'draft',
    contractOption: contractOption,
    contract: contractStatus == null
        ? null
        : BookingContract(id: 9, status: contractStatus),
    contacts: withContact
        ? const [
            BookingContact(
                id: 7, name: 'Claire', email: 'c@x.com', phone: '', role: ''),
          ]
        : const [],
    events: const [],
  );
}

Widget _wrap(Widget child) => CupertinoApp(home: Center(child: child));

void main() {
  testWidgets('prompts to add a contact when a pending contract has none',
      (tester) async {
    var addContactTapped = false;
    await tester.pumpWidget(_wrap(BookingContractNudge(
      booking: _booking(),
      onAddContact: () => addContactTapped = true,
      onSendContract: () {},
    )));

    expect(find.textContaining('Add a contact'), findsOneWidget);

    await tester.tap(find.text('Add contact'));
    expect(addContactTapped, isTrue);
  });

  testWidgets('prompts to send once contacts exist and contract is unsent',
      (tester) async {
    var sendTapped = false;
    await tester.pumpWidget(_wrap(BookingContractNudge(
      booking: _booking(withContact: true),
      onAddContact: () {},
      onSendContract: () => sendTapped = true,
    )));

    expect(find.textContaining('ready to send'), findsOneWidget);

    await tester.tap(find.text('Go to contract'));
    expect(sendTapped, isTrue);
  });

  testWidgets('renders nothing when the contract was already sent',
      (tester) async {
    await tester.pumpWidget(_wrap(BookingContractNudge(
      booking: _booking(withContact: true, contractStatus: 'sent'),
      onAddContact: () {},
      onSendContract: () {},
    )));
    expect(find.byType(CupertinoButton), findsNothing);
  });

  testWidgets('renders nothing for no-contract and external bookings',
      (tester) async {
    await tester.pumpWidget(_wrap(BookingContractNudge(
      booking: _booking(contractOption: 'none', contractStatus: null),
      onAddContact: () {},
      onSendContract: () {},
    )));
    expect(find.byType(CupertinoButton), findsNothing);

    await tester.pumpWidget(_wrap(BookingContractNudge(
      booking: _booking(contractOption: 'external'),
      onAddContact: () {},
      onSendContract: () {},
    )));
    expect(find.byType(CupertinoButton), findsNothing);
  });

  testWidgets('can be dismissed', (tester) async {
    await tester.pumpWidget(_wrap(BookingContractNudge(
      booking: _booking(),
      onAddContact: () {},
      onSendContract: () {},
    )));

    expect(find.textContaining('Add a contact'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.xmark));
    await tester.pumpAndSettle();

    expect(find.textContaining('Add a contact'), findsNothing);
  });
}
