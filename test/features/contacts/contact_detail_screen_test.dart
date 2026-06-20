import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
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

    testWidgets('shows a Send Message row when a phone is present',
        (tester) async {
      await tester.pumpWidget(_wrap(const ContactDetailScreen(
        contact: ContactRef(name: 'Texter', phone: '555-123-4567'),
      )));

      expect(find.text('Send Message'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chat_bubble), findsOneWidget);
    });

    testWidgets('omits Send Message row when no phone', (tester) async {
      await tester.pumpWidget(_wrap(const ContactDetailScreen(
        contact: ContactRef(name: 'Emailer', email: 'a@b.com'),
      )));

      expect(find.text('Send Message'), findsNothing);
    });

    group('copy fallback', () {
      String? copied;

      setUp(() {
        copied = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
      });

      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      testWidgets('copies the email when its copy button is tapped',
          (tester) async {
        await tester.pumpWidget(_wrap(const ContactDetailScreen(
          contact: ContactRef(
            name: 'Eddie Mullins',
            email: 'eddie@example.com',
            phone: '555-123-4567',
          ),
        )));

        // The first copy button (doc_on_doc) belongs to the email row.
        await tester.tap(find.byIcon(CupertinoIcons.doc_on_doc).first);
        await tester.pump();

        expect(copied, 'eddie@example.com');
        expect(find.text('Email copied'), findsOneWidget);

        // Let the toast's auto-dismiss timer fire so no timers leak.
        await tester.pump(const Duration(milliseconds: 1500));
      });

      testWidgets('copies the phone when its copy button is tapped',
          (tester) async {
        await tester.pumpWidget(_wrap(const ContactDetailScreen(
          contact: ContactRef(
            name: 'Eddie Mullins',
            email: 'eddie@example.com',
            phone: '555-123-4567',
          ),
        )));

        // The second copy button belongs to the phone row.
        await tester.tap(find.byIcon(CupertinoIcons.doc_on_doc).at(1));
        await tester.pump();

        expect(copied, '555-123-4567');
        expect(find.text('Phone copied'), findsOneWidget);

        // Let the toast's auto-dismiss timer fire so no timers leak.
        await tester.pump(const Duration(milliseconds: 1500));
      });
    });
  });
}
