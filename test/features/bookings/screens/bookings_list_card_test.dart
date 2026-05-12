import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';
import 'package:tts_bandmate/features/bookings/widgets/booking_list_card.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

BookingSummary _booking({
  required int id,
  required String name,
  required String startDate,
  String? endDate,
  int eventCount = 1,
  bool? isMultiEvent,
  String? venueSummary,
  List<EventSummary> events = const [],
}) {
  return BookingSummary(
    id: id,
    name: name,
    startDate: startDate,
    endDate: endDate ?? startDate,
    eventCount: eventCount,
    isMultiEvent: isMultiEvent ?? (eventCount > 1),
    venueSummary: venueSummary,
    isPaid: false,
    contacts: const [],
    events: events,
  );
}

void main() {
  testWidgets('single-event booking shows no chip and the single-event subtitle',
      (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(
        child: BookingListCard(
          booking: _booking(
            id: 1,
            name: 'Solo',
            startDate: '2026-06-13',
            venueSummary: 'Symphony Hall',
          ),
        ),
      ),
    ));

    expect(find.text('Solo'), findsOneWidget);
    // No multi-event chip: the only "events" text that could appear would be
    // in the chip label "N events"; single-event cards must not render it.
    expect(find.textContaining('events'), findsNothing,
        reason: 'single-event card should have no "N events" chip');
    // Venue appears in the venue row (below the subtitle).
    expect(find.textContaining('Symphony Hall'), findsWidgets);
  });

  testWidgets('multi-event booking shows chip and the multi-event subtitle',
      (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(
        child: BookingListCard(
          booking: _booking(
            id: 2,
            name: 'Three Show Run',
            startDate: '2026-06-13',
            endDate: '2026-06-15',
            eventCount: 3,
            venueSummary: 'Symphony Hall',
          ),
        ),
      ),
    ));

    expect(find.text('Three Show Run'), findsOneWidget);
    // The inline chip must appear.
    expect(find.text('3 events'), findsOneWidget,
        reason: 'multi-event card should render the "3 events" chip');
    // Venue appears somewhere in the card (subtitle and/or venue row).
    expect(find.textContaining('Symphony Hall'), findsWidgets);
  });
}
