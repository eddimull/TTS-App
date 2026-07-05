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

// Create-mode: an event whose title was left blank inherits the booking name
// at save time, so single-event bookings don't require typing the same name
// twice (and don't end up as "Untitled event").

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

Future<_CapturingRepo> _pumpAndFillForm(
  WidgetTester tester, {
  String? eventTitle,
}) async {
  final repo = _CapturingRepo();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eventTypesProvider.overrideWith(
          (_) async => [const EventType(id: 1, name: 'Concert')],
        ),
        bookingsRepositoryProvider.overrideWithValue(repo),
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
                        const BookingFormScreen(bandId: 1, existing: null),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // Push the form so the post-save pop has a route to return to.
  await tester.tap(find.text('Open form'));
  await tester.pumpAndSettle();

  // Booking name — the first text field on the screen.
  await tester.enterText(find.byType(EditableText).first, 'Summer Festival');
  await tester.pumpAndSettle();

  // Event type (picker defaults to the first entry, "Concert").
  await tester.tap(find.text('Select'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();

  // Optionally give the event row its own title.
  if (eventTitle != null) {
    await tester.enterText(
        find.widgetWithText(CupertinoTextField, 'Title'), eventTitle);
    await tester.pumpAndSettle();
  }

  // Start time — tap the row, accept the default via Done.
  await tester.ensureVisible(find.text('Start time'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start time'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Save Booking'));
  await tester.pumpAndSettle();

  return repo;
}

void main() {
  testWidgets('blank event title defaults to the booking name on save',
      (tester) async {
    final repo = await _pumpAndFillForm(tester);

    expect(repo.capturedEvents, isNotNull,
        reason: 'createBooking should have been called');
    expect(repo.capturedEvents!.single.title, 'Summer Festival');
  });

  testWidgets('a user-typed event title is not overwritten', (tester) async {
    final repo = await _pumpAndFillForm(tester, eventTitle: 'Ceremony');

    expect(repo.capturedEvents, isNotNull,
        reason: 'createBooking should have been called');
    expect(repo.capturedEvents!.single.title, 'Ceremony');
  });
}
