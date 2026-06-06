import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contact.dart';
import 'package:tts_bandmate/features/bookings/widgets/contract/contract_signature_block.dart';

void main() {
  Finder richTextContaining(String text) => find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains(text),
      );

  Widget wrap(Widget child) => CupertinoApp(
        home: CupertinoPageScaffold(child: child),
      );

  group('ContractSignatureBlock', () {
    const signer = BookingContact(id: 1, name: 'Mayor Jane Doe');

    testWidgets('no override shows signer name, no "on behalf of"',
        (t) async {
      await t.pumpWidget(wrap(
        const ContractSignatureBlock(firstContact: signer),
      ));

      expect(richTextContaining('Mayor Jane Doe'), findsWidgets);
      expect(richTextContaining('on behalf of'), findsNothing);
    });

    testWidgets('override shows buyer name and "on behalf of" signer',
        (t) async {
      await t.pumpWidget(wrap(
        const ContractSignatureBlock(
          firstContact: signer,
          buyerNameOverride: 'The City of Scott',
        ),
      ));

      expect(richTextContaining('The City of Scott'), findsWidgets);
      expect(richTextContaining('on behalf of'), findsOneWidget);
      expect(richTextContaining('Mayor Jane Doe'), findsWidgets);
    });

    testWidgets('whitespace-only override falls back, no "on behalf of"',
        (t) async {
      await t.pumpWidget(wrap(
        const ContractSignatureBlock(
          firstContact: signer,
          buyerNameOverride: '   ',
        ),
      ));

      expect(richTextContaining('Mayor Jane Doe'), findsWidgets);
      expect(richTextContaining('on behalf of'), findsNothing);
    });
  });
}
