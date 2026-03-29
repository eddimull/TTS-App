import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/widgets/event_card.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

EventSummary _makeEvent({
  String key = 'test-key',
  String title = 'Corporate Gig',
  String date = '2026-04-15',
  String? time = '19:00',
  String source = 'booking',
  String? status = 'confirmed',
  String? venueName = 'The Grand Hotel',
  int? liveSessionId,
}) =>
    EventSummary.fromJson({
      'id': 1,
      'key': key,
      'title': title,
      'date': date,
      'time': time,
      'event_source': source,
      'status': status,
      'venue_name': venueName,
      'live_session_id': liveSessionId,
    });

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(body: child),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('EventCard', () {
    testWidgets('test_renders_title_and_venue', (tester) async {
      await tester.pumpWidget(_wrap(EventCard(event: _makeEvent())));

      expect(find.text('Corporate Gig'), findsOneWidget);
      expect(find.text('The Grand Hotel'), findsOneWidget);
    });

    testWidgets('test_renders_confirmed_status_chip', (tester) async {
      await tester.pumpWidget(_wrap(EventCard(event: _makeEvent(status: 'confirmed'))));

      expect(find.text('Confirmed'), findsOneWidget);
    });

    testWidgets('test_renders_pending_status_chip', (tester) async {
      await tester.pumpWidget(_wrap(EventCard(event: _makeEvent(status: 'pending'))));

      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('test_renders_cancelled_status_chip', (tester) async {
      await tester.pumpWidget(_wrap(EventCard(event: _makeEvent(status: 'cancelled'))));

      expect(find.text('Cancelled'), findsOneWidget);
    });

    testWidgets('test_does_not_render_status_chip_when_status_null', (tester) async {
      await tester.pumpWidget(_wrap(EventCard(event: _makeEvent(status: null))));

      // No chip text — SizedBox.shrink is rendered instead
      expect(find.text('Confirmed'), findsNothing);
      expect(find.text('Pending'), findsNothing);
    });

    testWidgets('test_shows_live_session_badge_when_session_active', (tester) async {
      await tester.pumpWidget(_wrap(
        EventCard(event: _makeEvent(liveSessionId: 7)),
      ));

      // The live badge is a music_note icon
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });

    testWidgets('test_no_live_badge_when_no_session', (tester) async {
      await tester.pumpWidget(_wrap(EventCard(event: _makeEvent())));

      expect(find.byIcon(Icons.music_note), findsNothing);
    });

    testWidgets('test_does_not_render_venue_when_null', (tester) async {
      await tester.pumpWidget(_wrap(EventCard(event: _makeEvent(venueName: null))));

      expect(find.text('The Grand Hotel'), findsNothing);
    });

    testWidgets('test_rehearsal_uses_fitness_icon', (tester) async {
      await tester.pumpWidget(_wrap(EventCard(event: _makeEvent(source: 'rehearsal'))));

      expect(find.byIcon(Icons.fitness_center_outlined), findsOneWidget);
      expect(find.byIcon(Icons.event_available_outlined), findsNothing);
    });

    testWidgets('test_booking_uses_event_available_icon', (tester) async {
      await tester.pumpWidget(_wrap(EventCard(event: _makeEvent(source: 'booking'))));

      expect(find.byIcon(Icons.event_available_outlined), findsOneWidget);
    });

    testWidgets('test_on_tap_callback_is_invoked', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        EventCard(event: _makeEvent(), onTap: () => tapped = true),
      ));

      await tester.tap(find.byType(InkWell).first);
      expect(tapped, isTrue);
    });

    testWidgets('test_date_includes_time_when_present', (tester) async {
      await tester.pumpWidget(_wrap(EventCard(event: _makeEvent(time: '20:00'))));

      // The formatted date string should include the time
      expect(find.textContaining('20:00'), findsOneWidget);
    });

    testWidgets('test_date_excludes_time_when_null', (tester) async {
      await tester.pumpWidget(_wrap(EventCard(event: _makeEvent(time: null))));

      expect(find.textContaining('at'), findsNothing);
    });
  });
}
