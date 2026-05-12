import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/widgets/booking_engagement_summary.dart';

BookingDetail _booking({
  required int id,
  required String name,
  required String startDate,
  String? endDate,
  int eventCount = 1,
  bool? isMultiEvent,
  String? venueSummary,
}) {
  return BookingDetail(
    id: id,
    name: name,
    startDate: startDate,
    endDate: endDate ?? startDate,
    eventCount: eventCount,
    isMultiEvent: isMultiEvent ?? (eventCount > 1),
    venueSummary: venueSummary,
    isPaid: false,
    contacts: const [],
    payments: const [],
    events: const [],
  );
}

void main() {
  testWidgets('single-event subtitle reads "1 event · …" and no chip rendered',
      (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: BookingEngagementSummary(
        booking: _booking(
          id: 1,
          name: 'Solo Show',
          startDate: '2026-06-13',
          venueSummary: 'Symphony Hall',
        ),
      ),
    ));
    expect(find.text('Solo Show'), findsNothing,
        reason: 'name is not rendered by this widget');
    // The subtitle starts with "1 event · ..."
    expect(find.textContaining('1 event'), findsOneWidget);
    // Should not have the plural "1 events" form
    expect(find.text('1 events'), findsNothing,
        reason: 'singular subtitle uses "1 event", not "1 events"');
  });

  testWidgets('multi-event subtitle reads "N events · ..." and chip is present',
      (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: BookingEngagementSummary(
        booking: _booking(
          id: 2,
          name: 'Three Show Run',
          startDate: '2026-06-13',
          endDate: '2026-06-15',
          eventCount: 3,
          venueSummary: 'Symphony Hall',
        ),
      ),
    ));
    // The chip text "3 events" is rendered (chip is separate from subtitle)
    expect(find.text('3 events'), findsWidgets,
        reason: 'chip text should be present for multi-event booking');
    // The subtitle also contains "3 events"
    expect(find.textContaining('3 events'), findsWidgets);
  });

  testWidgets('chip absent on single-event bookings', (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: BookingEngagementSummary(
        booking: _booking(
          id: 3,
          name: 'Solo',
          startDate: '2026-06-13',
          eventCount: 1,
          venueSummary: 'Hall',
        ),
      ),
    ));
    // No plural "events" wording anywhere — only "1 event" (singular)
    expect(find.textContaining('events'), findsNothing,
        reason: 'no chip and no "N events" plural for single-event booking');
    expect(find.textContaining('1 event'), findsOneWidget);
  });
}
