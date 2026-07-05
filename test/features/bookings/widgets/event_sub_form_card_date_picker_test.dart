import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_date_status.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_draft.dart';
import 'package:tts_bandmate/features/bookings/data/venue_search_service.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/bookings/widgets/event_sub_form_card.dart';

// The event date field opens a month-grid calendar that marks dates already
// holding a booking (confirmed/pending/draft), instead of a blind wheel
// picker — parity with the web app's reserved-dates calendar.

class _FakeVenueSearchService implements VenueSearchService {
  @override
  Future<List<VenuePrediction>> search(String query) async => [];
}

Widget _wrap(Widget child, {Map<String, BookingDateInfo>? dateInfo}) {
  return ProviderScope(
    overrides: [
      venueSearchServiceProvider.overrideWithValue(_FakeVenueSearchService()),
      bookingDateInfoProvider.overrideWith(
        (ref, bandId) async => dateInfo ?? const {},
      ),
    ],
    child: CupertinoApp(
      home: Center(child: child),
    ),
  );
}

Map<String, BookingDateInfo> _juneWedding({int bookingId = 7}) => {
      '2026-06-20': BookingDateInfo(
        status: BookingDateStatus.confirmed,
        bookingTitle: 'The Grand Wedding',
        bookingId: bookingId,
      ),
    };

void main() {
  testWidgets('tapping the date row opens the reserved-dates calendar',
      (tester) async {
    await tester.pumpWidget(_wrap(
      EventSubFormCard(
        bandId: 1,
        draft: const EventDraft(title: 'X', date: '2026-06-13'),
        canDelete: true,
        onChange: (_) {},
        onDelete: () {},
      ),
      dateInfo: _juneWedding(),
    ));

    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();

    // Month grid with legend, not a wheel.
    expect(find.text('June 2026'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsNothing);
  });

  testWidgets('selecting a booked day surfaces the existing booking',
      (tester) async {
    await tester.pumpWidget(_wrap(
      EventSubFormCard(
        bandId: 1,
        draft: const EventDraft(title: 'X', date: '2026-06-13'),
        canDelete: true,
        onChange: (_) {},
        onDelete: () {},
      ),
      dateInfo: _juneWedding(),
    ));

    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();

    expect(find.text('The Grand Wedding'), findsOneWidget);
  });

  testWidgets('Done applies the tapped date to the draft', (tester) async {
    EventDraft? changed;
    await tester.pumpWidget(_wrap(
      EventSubFormCard(
        bandId: 1,
        draft: const EventDraft(title: 'X', date: '2026-06-13'),
        canDelete: true,
        onChange: (d) => changed = d,
        onDelete: () {},
      ),
      dateInfo: _juneWedding(),
    ));

    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(changed?.date, '2026-06-20');
  });

  testWidgets('the booking being edited does not flag its own date',
      (tester) async {
    await tester.pumpWidget(_wrap(
      EventSubFormCard(
        bandId: 1,
        excludeBookingId: 7,
        draft: const EventDraft(title: 'X', date: '2026-06-13'),
        canDelete: true,
        onChange: (_) {},
        onDelete: () {},
      ),
      dateInfo: _juneWedding(bookingId: 7),
    ));

    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();

    expect(find.text('The Grand Wedding'), findsNothing);
  });
}
