import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_draft.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_type.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/bookings/screens/booking_form_screen.dart';
import 'package:tts_bandmate/features/bookings/utils/new_booking_navigation.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';

// After a successful create, the user should land on the new booking's
// detail screen — not back on the bookings list with no signpost.
//
// Split across the two halves of the flow:
//  1. The form pops with the created BookingDetail as its route result.
//  2. pushNewBookingForm (used by the bookings list and dashboard) awaits
//     that result and forwards to /bookings/:bandId/:id.

BookingDetail _created({int id = 42}) => BookingDetail(
      id: id,
      name: 'Summer Festival',
      startDate: '2026-08-01',
      endDate: '2026-08-01',
      eventCount: 1,
      isMultiEvent: false,
      isPaid: false,
      status: 'draft',
      contractOption: 'default',
      contacts: const [],
      events: const [],
      band: const BandSummary(id: 1, name: 'Band', isOwner: true),
    );

/// No-op: the real invalidator reads storage/dashboard providers that have
/// no test overrides here, and invalidation behavior is not under test.
class _NoopInvalidator extends CacheInvalidator {
  _NoopInvalidator(super.ref);

  @override
  void onBookingChanged({required int bandId, int? bookingId}) {}
}

class _FakeRepo extends BookingsRepository {
  _FakeRepo() : super(Dio());

  @override
  Future<BookingDetail> createBooking(
    int bandId, {
    required String name,
    required int eventTypeId,
    String? price,
    String? status,
    String? contractOption,
    String? notes,
    String? depositType,
    String? depositValue,
    required List<EventDraft> events,
  }) async {
    return _created();
  }
}

void main() {
  testWidgets('form pops with the created BookingDetail as its result',
      (tester) async {
    Object? popResult;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventTypesProvider.overrideWith(
            (_) async => [const EventType(id: 1, name: 'Concert')],
          ),
          bookingsRepositoryProvider.overrideWithValue(_FakeRepo()),
          cacheInvalidatorProvider.overrideWith(_NoopInvalidator.new),
        ],
        child: CupertinoApp(
          home: Builder(
            builder: (context) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  child: const Text('Open form'),
                  onPressed: () async {
                    popResult = await Navigator.of(context).push<Object?>(
                      CupertinoPageRoute(
                        builder: (_) => const BookingFormScreen(
                            bandId: 1, existing: null),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, 'Summer Festival');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Start time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Booking'));
    await tester.pumpAndSettle();

    // No error dialog: the save path must have completed cleanly.
    expect(find.text('Error'), findsNothing);
    // The form route must have popped back to the host screen.
    expect(find.text('Open form'), findsOneWidget);
    expect(popResult, isA<BookingDetail>());
    expect((popResult as BookingDetail).id, 42);
  });

  testWidgets(
      'pushNewBookingForm forwards to the booking detail route after create',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Builder(
            builder: (context) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  child: const Text('New booking'),
                  onPressed: () => pushNewBookingForm(context, 1),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/bookings/:bandId/new',
          // Stand-in for the form: pops immediately with a created booking.
          builder: (_, __) => Builder(
            builder: (context) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  child: const Text('Fake save'),
                  onPressed: () => Navigator.of(context).pop(_created()),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/bookings/:bandId/:id',
          builder: (_, state) => CupertinoPageScaffold(
            child: Center(
              child: Text('DETAIL ${state.pathParameters['id']}'),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(CupertinoApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New booking'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fake save'));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL 42'), findsOneWidget);
  });
}
