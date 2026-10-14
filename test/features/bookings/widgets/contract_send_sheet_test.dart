import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contact.dart';
import 'package:tts_bandmate/features/bookings/widgets/contract/contract_send_sheet.dart';

const _contacts = [
  BookingContact(id: 1, name: 'Alice A', email: 'a@x.com'),
  BookingContact(id: 2, name: 'Bob B', email: 'b@x.com'),
  BookingContact(id: 3, name: 'Cy C', email: null),
];

void main() {
  ContractSendSheetResult? result;
  var resolved = false;

  Future<void> open(WidgetTester t, List<BookingContact> contacts) async {
    result = null;
    resolved = false;
    await t.pumpWidget(CupertinoApp(
      home: Builder(
        builder: (ctx) => CupertinoButton(
          onPressed: () async {
            result = await showContractSendSheet(ctx, contacts: contacts);
            resolved = true;
          },
          child: const Text('Open'),
        ),
      ),
    ));
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
  }

  // Tap the segment labelled [label] in the row belonging to [name].
  Future<void> choose(WidgetTester t, String name, String label) async {
    final row = find
        .ancestor(of: find.text(name), matching: find.byType(Column))
        .first;
    await t.tap(find.descendant(of: row, matching: find.text(label)));
    await t.pumpAndSettle();
  }

  bool sendEnabled(WidgetTester t) {
    final btn = t.widget<CupertinoButton>(
      find.ancestor(
        of: find.text('Send'),
        matching: find.byType(CupertinoButton),
      ),
    );
    return btn.onPressed != null;
  }

  testWidgets('defaults first contact to signer, others none', (t) async {
    await open(t, _contacts);
    expect(sendEnabled(t), isTrue);
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(result!.signerIds, [1]);
    expect(result!.ccIds, isEmpty);
  });

  testWidgets('toggling roles yields multiple signers and CCs', (t) async {
    await open(t, [
      ..._contacts.take(2),
      const BookingContact(id: 4, name: 'Dee D', email: 'd@x.com'),
    ]);
    await choose(t, 'Bob B', 'Signer');
    await choose(t, 'Dee D', 'CC');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(result!.signerIds, [1, 2]);
    expect(result!.ccIds, [4]);
  });

  testWidgets('send disabled with no signer', (t) async {
    await open(t, _contacts);
    await choose(t, 'Alice A', 'None');
    expect(sendEnabled(t), isFalse);
    await t.tap(find.text('Send'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(resolved, isFalse);
    expect(find.text('Choose at least one signer.'), findsOneWidget);
  });

  testWidgets('contact without email is disabled and explained', (t) async {
    await open(t, _contacts);
    expect(find.textContaining('No email address'), findsOneWidget);
    await choose(t, 'Cy C', 'Signer');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(result!.signerIds, [1]);
  });

  testWidgets('cancel returns null', (t) async {
    await open(t, _contacts);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(resolved, isTrue);
    expect(result, isNull);
  });

  testWidgets('many contacts fit a narrow phone without overflow', (t) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await open(t, [
      for (var i = 1; i <= 12; i++)
        BookingContact(id: i, name: 'Person $i', email: 'p$i@x.com'),
    ]);
    expect(t.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
  });
}
