import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contract.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/widgets/contract/contract_default_view.dart';

void main() {
  testWidgets('locked status shows banner and segmented control', (t) async {
    const booking = BookingDetail(
      id: 1,
      name: 'X',
      startDate: '2026-05-11',
      endDate: '2026-05-11',
      eventCount: 1,
      isMultiEvent: false,
      isPaid: false,
      contacts: [],
      events: [],
      status: 'pending',
      contractOption: 'default',
      contract: BookingContract(id: 1, envelopeId: 'env-1'),
      band: BandSummary(id: 1, name: 'Band', isOwner: true),
    );

    await t.pumpWidget(const ProviderScope(
      child: CupertinoApp(home: ContractDefaultView(booking: booking)),
    ));
    // Banner asserts something about "pending" status
    expect(find.textContaining('pending'), findsWidgets);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
  });
}
