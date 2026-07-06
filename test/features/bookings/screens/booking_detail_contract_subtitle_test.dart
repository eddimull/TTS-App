import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contract.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/bookings/screens/booking_detail_screen.dart';

// The contracts table's initial status is 'pending' ("not sent yet"), but
// for bookings 'pending' means "out for signature". Showing the raw contract
// status on the detail screen's Contract tile made a freshly created draft
// booking read as "Pending" — the subtitle must say "Not sent yet" until the
// contract is actually sent.

BookingDetail _detail({String? contractStatus}) => BookingDetail(
      id: 1,
      name: 'Subtitle Test',
      startDate: '2026-08-01',
      endDate: '2026-08-01',
      eventCount: 1,
      isMultiEvent: false,
      isPaid: false,
      status: 'draft',
      contractOption: 'default',
      contract: contractStatus == null
          ? null
          : BookingContract(id: 9, status: contractStatus),
      contacts: const [],
      events: const [],
      band: const BandSummary(id: 1, name: 'Band', isOwner: true),
    );

Future<void> _pump(WidgetTester tester, BookingDetail detail) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookingDetailProvider.overrideWith((ref, args) async => detail),
      ],
      child: const CupertinoApp(
        home: BookingDetailScreen(bandId: 1, bookingId: 1),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('unsent contract reads "Not sent yet", not "Pending"',
      (tester) async {
    await _pump(tester, _detail(contractStatus: 'pending'));

    await tester.scrollUntilVisible(
      find.text('Not sent yet'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Not sent yet'), findsOneWidget);
    expect(find.text('Pending'), findsNothing);
  });

  testWidgets('sent contract still reads "Sent"', (tester) async {
    await _pump(tester, _detail(contractStatus: 'sent'));

    await tester.scrollUntilVisible(
      find.text('Sent'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sent'), findsOneWidget);
  });
}
