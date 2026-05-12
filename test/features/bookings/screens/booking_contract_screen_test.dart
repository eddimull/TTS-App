import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/bookings/screens/booking_contract_screen.dart';

// Minimal BookingDetail with only the fields the contract screen reads.
BookingDetail _makeDetail({required String contractOption}) {
  return BookingDetail(
    id: 1,
    name: 'Test Booking',
    startDate: '2025-06-01',
    endDate: '2025-06-01',
    eventCount: 1,
    isMultiEvent: false,
    isPaid: false,
    contacts: const [],
    events: const [],
    contractOption: contractOption,
  );
}

// Pump BookingContractScreen with the bookingDetailProvider overridden so it
// returns immediately with the supplied BookingDetail.
Future<void> _pumpScreen(
  WidgetTester tester, {
  required String contractOption,
}) async {
  final detail = _makeDetail(contractOption: contractOption);
  const bandId = 1;
  const bookingId = 1;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookingDetailProvider
            .overrideWith((ref, args) async => detail),
      ],
      child: const CupertinoApp(
        home: BookingContractScreen(bandId: bandId, bookingId: bookingId),
      ),
    ),
  );

  // Let the FutureProvider resolve.
  await tester.pump();
}

void main() {
  testWidgets(
    'renders verbal-agreement copy for contractOption == "none"',
    (tester) async {
      await _pumpScreen(tester, contractOption: 'none');

      expect(
        find.text('Verbal agreement — no contract on file'),
        findsOneWidget,
      );
      expect(find.text('Change to a contract type'), findsOneWidget);
    },
  );

  testWidgets(
    'does NOT render verbal-agreement copy for contractOption == "default"',
    (tester) async {
      await _pumpScreen(tester, contractOption: 'default');

      expect(
        find.text('Verbal agreement — no contract on file'),
        findsNothing,
      );
      expect(find.text('Change to a contract type'), findsNothing);
    },
  );

  testWidgets(
    'does NOT render verbal-agreement copy for contractOption == "external"',
    (tester) async {
      await _pumpScreen(tester, contractOption: 'external');

      expect(
        find.text('Verbal agreement — no contract on file'),
        findsNothing,
      );
      expect(find.text('Change to a contract type'), findsNothing);
    },
  );
}
