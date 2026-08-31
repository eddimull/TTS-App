import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_draft.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_type.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/bookings/screens/booking_form_screen.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';

// Create mode is streamlined to match the web booking form: one flat
// schedule (date, start time, duration) with no event title, no end-time
// picker, and no multi-event management. The single event is derived at
// save: title = booking name, end_time = start + duration.

class _NoopInvalidator extends CacheInvalidator {
  _NoopInvalidator(super.ref);

  @override
  void onBookingChanged({required int bandId, int? bookingId}) {}
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
      startDate: '2026-08-01',
      endDate: '2026-08-01',
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

Future<_CapturingRepo> _pumpForm(
  WidgetTester tester, {
  BookingDetail? existing,
}) async {
  final repo = _CapturingRepo();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eventTypesProvider.overrideWith(
          (_) async => [const EventType(id: 1, name: 'Concert')],
        ),
        bookingsRepositoryProvider.overrideWithValue(repo),
        cacheInvalidatorProvider.overrideWith(_NoopInvalidator.new),
      ],
      child: CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                child: const Text('Open form'),
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) =>
                        BookingFormScreen(bandId: 1, existing: existing),
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

Future<void> _fillNameAndType(WidgetTester tester) async {
  await tester.enterText(find.byType(EditableText).first, 'Summer Festival');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
}

Future<void> _pickDefaultStartTime(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Start time'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start time'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
}

BookingDetail _existingBooking() {
  return const BookingDetail(
    id: 7,
    name: 'Existing gig',
    startDate: '2026-09-01',
    endDate: '2026-09-01',
    eventCount: 1,
    isMultiEvent: false,
    isPaid: false,
    status: 'pending',
    contacts: [],
    events: [
      EventSummary(
        id: 11,
        key: 'evt-key-11',
        title: 'Existing gig',
        date: '2026-09-01',
        startTime: '19:00',
        endTime: '23:00',
        eventSource: 'booking',
      ),
    ],
    band: BandSummary(id: 1, name: 'Band', isOwner: true),
  );
}

void main() {
  testWidgets('create mode shows streamlined schedule instead of event cards',
      (tester) async {
    await _pumpForm(tester);

    expect(find.text('Untitled event'), findsNothing);
    expect(find.widgetWithText(CupertinoTextField, 'Title'), findsNothing);
    expect(find.text('End time'), findsNothing);
    expect(find.text('+ Add event'), findsNothing);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('4 hr'), findsOneWidget);
  });

  testWidgets('save derives end time from start time plus duration',
      (tester) async {
    final repo = await _pumpForm(tester);
    await _fillNameAndType(tester);
    // Picker defaults to 19:00 for start.
    await _pickDefaultStartTime(tester);

    await tester.tap(find.text('Save Booking'));
    await tester.pumpAndSettle();

    expect(repo.capturedEvents, isNotNull,
        reason: 'createBooking should have been called');
    final event = repo.capturedEvents!.single;
    expect(event.title, 'Summer Festival');
    expect(event.startTime, '19:00');
    expect(event.endTime, '23:00');
  });

  testWidgets('duration stepper adjusts the derived end time, wrapping midnight',
      (tester) async {
    final repo = await _pumpForm(tester);
    await _fillNameAndType(tester);
    await _pickDefaultStartTime(tester);

    // 4 hr -> 5 hr; 19:00 + 5h = 00:00 next day.
    await tester.ensureVisible(find.byIcon(CupertinoIcons.plus_circle));
    await tester.tap(find.byIcon(CupertinoIcons.plus_circle));
    await tester.pumpAndSettle();
    expect(find.text('5 hr'), findsOneWidget);

    await tester.tap(find.text('Save Booking'));
    await tester.pumpAndSettle();

    expect(repo.capturedEvents!.single.endTime, '00:00');
  });

  testWidgets('edit mode keeps full event cards', (tester) async {
    await _pumpForm(tester, existing: _existingBooking());

    expect(find.widgetWithText(CupertinoTextField, 'Title'), findsOneWidget);
    expect(find.text('+ Add event'), findsOneWidget);
    expect(find.text('End time'), findsOneWidget);
    expect(find.text('Duration'), findsNothing);
  });
}
