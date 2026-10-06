import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_draft.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_type.dart';
import 'package:tts_bandmate/features/bookings/data/venue_search_service.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/bookings/screens/booking_form_screen.dart';
import 'package:tts_bandmate/features/bookings/widgets/booking_calendar_picker.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';

// Pinned mid-month so 'next month' is unambiguous for the whole test run.
final _pinned = DateTime(2026, 6, 15, 10);

/// Runs [body] with `clock.now()` fixed at [_pinned].
T _atPinned<T>(T Function() body) => withClock(Clock.fixed(_pinned), body);

// Creating a booking whose date was picked in a DIFFERENT month than today
// (calendar chevron navigation) must send the picked date, not today's, in
// the create payload — whether the sheet closes via Done or a barrier tap.

class _NoopInvalidator extends CacheInvalidator {
  _NoopInvalidator(super.ref);

  @override
  void onBookingChanged({required int bandId, int? bookingId}) {}
}

class _FakeVenueSearchService implements VenueSearchService {
  @override
  Future<List<VenuePrediction>> search(String query) async => [];
}

class _CapturingRepo extends BookingsRepository {
  _CapturingRepo() : super(Dio());

  List<EventDraft>? capturedEvents;

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
    capturedEvents = events;
    return BookingDetail(
      id: 42,
      name: name,
      startDate: events.first.date,
      endDate: events.first.date,
      eventCount: events.length,
      isMultiEvent: events.length > 1,
      isPaid: false,
      status: 'draft',
      contractOption: contractOption,
      contacts: const [],
      events: const [],
      band: const BandSummary(id: 1, name: 'Band', isOwner: true),
    );
  }
}

Future<_CapturingRepo> _pumpForm(WidgetTester tester) async {
  final repo = _CapturingRepo();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eventTypesProvider.overrideWith(
          (_) async => [const EventType(id: 1, name: 'Concert')],
        ),
        bookingsRepositoryProvider.overrideWithValue(repo),
        cacheInvalidatorProvider.overrideWith(_NoopInvalidator.new),
        venueSearchServiceProvider.overrideWithValue(_FakeVenueSearchService()),
        bookingDateInfoProvider.overrideWith((ref, bandId) async => const {}),
      ],
      child: CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                child: const Text('Open form'),
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const BookingFormScreen(bandId: 1),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open form'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets(
      'create sends the date picked in next month, not today', (tester) => _atPinned(() async {
    final repo = await _pumpForm(tester);

    // Name + event type.
    await tester.enterText(find.byType(EditableText).first, 'October Gig');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Open the date picker and navigate one month forward.
    await tester.ensureVisible(find.text('Date'));
    await tester.pumpAndSettle();
    // ensureVisible can leave the row tucked under the translucent nav bar;
    // pull the content down so the tap actually lands on the row.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();

    final nextMonthChevron = find.descendant(
      of: find.byType(BookingCalendarPicker),
      matching: find.byIcon(CupertinoIcons.chevron_right),
    );
    await tester.tap(nextMonthChevron);
    await tester.pumpAndSettle();

    // Tap the 15th of next month, then Done.
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Start time (defaults to 19:00 in the wheel).
    await tester.ensureVisible(find.text('Start time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Booking'));
    await tester.pumpAndSettle();

    expect(repo.capturedEvents, isNotNull,
        reason: 'createBooking should have been called');

    final now = clock.now();
    final nextMonth = DateTime(now.year, now.month + 1, 15);
    final expected = '${nextMonth.year}-'
        '${nextMonth.month.toString().padLeft(2, '0')}-15';
    expect(repo.capturedEvents!.single.date, expected);
  }));

  testWidgets(
      'dismissing the calendar without Done still keeps the tapped day',
      (tester) => _atPinned(() async {
    final repo = await _pumpForm(tester);

    await tester.enterText(find.byType(EditableText).first, 'October Gig');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Date'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();

    final nextMonthChevron = find.descendant(
      of: find.byType(BookingCalendarPicker),
      matching: find.byIcon(CupertinoIcons.chevron_right),
    );
    await tester.tap(nextMonthChevron);
    await tester.pumpAndSettle();

    // Tap the 15th of next month — then dismiss via the barrier (tap the
    // dimmed area above the sheet) instead of Done.
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Sheet is gone; pick a start time and save.
    await tester.ensureVisible(find.text('Start time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Booking'));
    await tester.pumpAndSettle();

    expect(repo.capturedEvents, isNotNull);

    final now = clock.now();
    final nextMonth = DateTime(now.year, now.month + 1, 15);
    final expected = '${nextMonth.year}-'
        '${nextMonth.month.toString().padLeft(2, '0')}-15';
    expect(repo.capturedEvents!.single.date, expected);
  }));
}
