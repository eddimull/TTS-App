import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/contacts/contact_detail_screen.dart';
import 'package:tts_bandmate/features/contacts/contact_ref.dart';

Widget _wrap(Widget child) => CupertinoApp(home: child);

void main() {
  group('ContactDetailScreen', () {
    testWidgets('renders name, initial, email and phone rows', (tester) async {
      await tester.pumpWidget(_wrap(const ContactDetailScreen(
        contact: ContactRef(
          name: 'Eddie Mullins',
          email: 'eddie@example.com',
          phone: '555-123-4567',
        ),
      )));

      expect(find.text('Eddie Mullins'), findsOneWidget);
      expect(find.text('E'), findsOneWidget); // avatar initial
      expect(find.text('eddie@example.com'), findsOneWidget);
      expect(find.text('555-123-4567'), findsOneWidget);
    });

    testWidgets('omits email/phone rows when no contact info', (tester) async {
      await tester.pumpWidget(_wrap(const ContactDetailScreen(
        contact: ContactRef(name: 'No Contact Info'),
      )));

      expect(find.text('No Contact Info'), findsOneWidget);
      // No mailto/tel rows rendered.
      expect(find.byIcon(CupertinoIcons.mail), findsNothing);
      expect(find.byIcon(CupertinoIcons.phone), findsNothing);
    });

    testWidgets('shows role and section context rows', (tester) async {
      await tester.pumpWidget(_wrap(const ContactDetailScreen(
        contact: ContactRef(
          name: 'Horn Player',
          role: 'Trumpet',
          section: 'HORNS',
        ),
      )));

      expect(find.text('Trumpet'), findsOneWidget);
      expect(find.text('HORNS'), findsOneWidget);
    });

    testWidgets('renders trailing actions when provided', (tester) async {
      await tester.pumpWidget(_wrap(ContactDetailScreen(
        contact: const ContactRef(name: 'Owner Person', isOwner: true),
        trailingActions: [
          CupertinoListTile(
            title: const Text('Manage permissions'),
            onTap: () {},
          ),
        ],
      )));

      expect(find.text('Manage permissions'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget); // role line falls back
    });

    testWidgets('falls back to "?" initial for empty name', (tester) async {
      await tester.pumpWidget(_wrap(const ContactDetailScreen(
        contact: ContactRef(name: ''),
      )));

      expect(find.text('?'), findsOneWidget);
    });
  });
}
