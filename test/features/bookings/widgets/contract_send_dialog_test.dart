import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contact.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/providers/contract_editor_provider.dart';
import 'package:tts_bandmate/features/bookings/widgets/contract/contract_editor.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeRepo extends BookingsRepository {
  _FakeRepo(this._detail) : super(Dio());

  final BookingDetail _detail;

  @override
  Future<BookingDetail> sendContract(int bandId, int bookingId, int signerId,
      {int? ccId}) async {
    return _detail;
  }

  @override
  Future<BookingDetail> saveContractTerms(
    int bandId,
    int bookingId,
    List terms, {
    String? buyerNameOverride,
  }) async {
    return _detail;
  }
}

/// Shared, eagerly-created flag holder so the test can read invalidation state
/// even before the provider is first read (it now fires only after OK).
class _InvalidationLog {
  bool detailChangedCalled = false;
}

/// Records whether (and when) cache invalidation fired so the test can assert
/// the success dialog is shown BEFORE the screen-rebuilding invalidation.
class _RecordingInvalidator extends CacheInvalidator {
  _RecordingInvalidator(super.ref, this._log);

  final _InvalidationLog _log;

  @override
  void onBookingDetailChanged({
    required int bandId,
    required int bookingId,
    String? contractEnvelopeId,
  }) {
    _log.detailChangedCalled = true;
    // Intentionally do NOT call super: invalidating real providers would tear
    // down the editor subtree (the very bug under test) and pull in unrelated
    // dashboard/auth providers. We only need to observe ordering here.
  }
}

BookingDetail _detail() => const BookingDetail(
      id: 1,
      name: 'Test Booking',
      startDate: '2025-06-01',
      endDate: '2025-06-01',
      eventCount: 1,
      isMultiEvent: false,
      isPaid: false,
      // Non-locked status so ContractDefaultView routes to ContractEditor.
      status: 'draft',
      contractOption: 'default',
      contacts: [
        BookingContact(
          id: 7,
          name: 'Claire Hoyt',
          email: 'clairevhoyt@yahoo.com',
          phone: '',
          role: '',
        ),
      ],
      events: [],
      band: BandSummary(id: 1, name: 'Band', isOwner: true),
    );

void main() {
  testWidgets(
    'Contract Sent dialog appears and dismisses on OK, and cache is '
    'invalidated only after the dialog is confirmed',
    (tester) async {
      final detail = _detail();
      final log = _InvalidationLog();

      const key = (bandId: 1, bookingId: 1);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookingsRepositoryProvider.overrideWithValue(_FakeRepo(detail)),
            cacheInvalidatorProvider.overrideWith(
              (ref) => _RecordingInvalidator(ref, log),
            ),
            // Give the editor a ready state without loading bundled assets.
            contractEditorProvider(key).overrideWith(
              () => _ReadyEditor(),
            ),
          ],
          child: CupertinoApp(
            home: ContractEditor(booking: detail),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Send → opens the signer sheet.
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Confirm signer (default selection) by tapping the sheet's Send button.
      // There are now two 'Send' texts (nav bar + sheet); tap the last one.
      await tester.tap(find.text('Send').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Success dialog must be visible…
      expect(find.text('Contract Sent'), findsOneWidget);
      // …and the cache must NOT have been invalidated yet (dialog-first).
      expect(log.detailChangedCalled, isFalse,
          reason: 'cache should be invalidated only after OK is tapped');

      // Dismiss it.
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Contract Sent'), findsNothing,
          reason: 'OK should dismiss the success dialog');
      expect(log.detailChangedCalled, isTrue,
          reason: 'cache should be invalidated after the dialog is confirmed');
    },
  );
}

class _ReadyEditor extends ContractEditorNotifier {
  _ReadyEditor() : super((bandId: 1, bookingId: 1));

  @override
  Future<ContractEditorState> build() async {
    return const ContractEditorState(terms: [], unsavedChanges: false);
  }

  @override
  Future<void> save({bool force = false}) async {}
}
