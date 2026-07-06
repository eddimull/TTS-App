import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contract.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/widgets/contract/contract_default_view.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';

class _FakeRepo extends BookingsRepository {
  _FakeRepo() : super(Dio());
  int amendCalls = 0;

  @override
  Future<BookingDetail> amendContract(int bandId, int bookingId) async {
    amendCalls++;
    return _booking(status: 'draft', contractStatus: 'pending');
  }
}

class _NoopInvalidator extends CacheInvalidator {
  _NoopInvalidator(super.ref);
  @override
  void onBookingDetailChanged(
      {required int bandId,
      required int bookingId,
      String? contractEnvelopeId}) {}
}

BookingDetail _booking({
  String status = 'pending',
  String contractStatus = 'sent',
  String contractOption = 'default',
}) =>
    BookingDetail(
      id: 42,
      name: 'Wedding',
      startDate: '2026-08-01',
      endDate: '2026-08-01',
      eventCount: 1,
      isMultiEvent: false,
      isPaid: false,
      status: status,
      contractOption: contractOption,
      contract: BookingContract(
          id: 9, status: contractStatus, envelopeId: 'pd-1'),
      contacts: const [],
      events: const [],
      band: const BandSummary(id: 1, name: 'Band', isOwner: true),
    );

Widget _wrap(BookingDetail booking, _FakeRepo repo) => ProviderScope(
      overrides: [
        bookingsRepositoryProvider.overrideWithValue(repo),
        cacheInvalidatorProvider.overrideWith(_NoopInvalidator.new),
      ],
      child: CupertinoApp(home: ContractDefaultView(booking: booking)),
    );

void main() {
  testWidgets('locked pending view shows Amend contract', (tester) async {
    await tester.pumpWidget(_wrap(_booking(), _FakeRepo()));
    await tester.pump();
    expect(find.text('Amend contract'), findsOneWidget);
  });

  testWidgets('confirmed (signed) view has no Amend button', (tester) async {
    await tester.pumpWidget(_wrap(
        _booking(status: 'confirmed', contractStatus: 'completed'),
        _FakeRepo()));
    await tester.pump();
    expect(find.text('Amend contract'), findsNothing);
  });

  testWidgets('confirm dialog cancel does not call the repo', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_wrap(_booking(), repo));
    await tester.pump();

    await tester.tap(find.text('Amend contract'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.amendCalls, 0);
  });

  testWidgets('confirming Amend calls the repository', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_wrap(_booking(), repo));
    await tester.pump();

    await tester.tap(find.text('Amend contract'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amend'));
    await tester.pumpAndSettle();

    expect(repo.amendCalls, 1);
  });
}
