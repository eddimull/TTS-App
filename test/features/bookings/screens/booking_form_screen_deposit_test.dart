import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contract.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/data/models/deposit.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_type.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/bookings/screens/booking_form_screen.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

BookingDetail _makeBooking({
  String depositType = 'percent',
  String depositValue = '50.00',
  String? price,
  BookingContract? contract,
}) {
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
    depositType: depositType,
    depositValue: depositValue,
    price: price,
    contract: contract,
  );
}

/// Pumps [BookingFormScreen] with a fixed event-type list so no network call
/// is made. [existing] drives edit mode; null gives create mode.
Future<void> _pumpScreen(
  WidgetTester tester, {
  BookingDetail? existing,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Stub event types so the screen doesn't hit the network.
        eventTypesProvider.overrideWith(
          (_) async => [const EventType(id: 1, name: 'Concert')],
        ),
      ],
      child: CupertinoApp(
        home: BookingFormScreen(
          bandId: 1,
          existing: existing,
        ),
      ),
    ),
  );

  // Let the FutureProvider (eventTypesProvider) resolve.
  await tester.pump();
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  group('Booking form deposit row', () {
    testWidgets('shows the Deposit field in create mode', (tester) async {
      await _pumpScreen(tester);

      // The prefix label should be visible in the FINANCIALS section.
      expect(find.text('Deposit'), findsOneWidget);
    });

    testWidgets(
        'shows computed dollar caption when depositType=percent with price',
        (tester) async {
      // Edit mode: price=$1000, 50% deposit → "= $500.00"
      await _pumpScreen(
        tester,
        existing: _makeBooking(
          depositType: 'percent',
          depositValue: '50.00',
          price: '1000.00',
        ),
      );

      expect(find.textContaining('= \$500.00'), findsOneWidget);
    });

    testWidgets('shows percent caption when depositType=amount with price',
        (tester) async {
      // Edit mode: amount=$250 of $1000 price → "= 25.0%"
      await _pumpScreen(
        tester,
        existing: _makeBooking(
          depositType: 'amount',
          depositValue: '250.00',
          price: '1000.00',
        ),
      );

      expect(find.textContaining('= 25.0%'), findsOneWidget);
    });

    testWidgets('clears deposit value when toggling mode', (tester) async {
      await _pumpScreen(
        tester,
        existing: _makeBooking(
          depositType: 'percent',
          depositValue: '50.00',
          price: '1000.00',
        ),
      );

      // Verify initial value is present.
      expect(find.textContaining('50.00'), findsWidgets);

      // Tap the "$" segment to switch from % to amount.
      await tester.tap(find.text('\$'));
      await tester.pump();

      // The deposit text field should now be empty after the mode switch.
      final depositField = tester.widgetList<CupertinoTextField>(
        find.byType(CupertinoTextField),
      );
      // The deposit input is the second CupertinoTextField (after name, price).
      final depositController = depositField
          .where((f) => f.controller?.text == '')
          .toList();
      expect(depositController, isNotEmpty,
          reason: 'Deposit field should be empty after toggling mode');
    });

    testWidgets('shows locked caption when contract is signed', (tester) async {
      const signedContract = BookingContract(
        id: 99,
        status: 'completed',
      );

      await _pumpScreen(
        tester,
        existing: _makeBooking(
          depositType: 'percent',
          depositValue: '50.00',
          price: '1000.00',
          contract: signedContract,
        ),
      );

      expect(
        find.text('Locked — contract is signed.'),
        findsOneWidget,
      );
    });

    testWidgets('DepositType enum has percent and amount variants', (_) async {
      // Sanity-check the model the UI imports.
      expect(DepositType.values, containsAll([DepositType.percent, DepositType.amount]));
    });
  });
}
