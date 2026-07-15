import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/dashboard/widgets/calendar_event_marker.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/shared/widgets/band_avatar.dart';

EventSummary _evt({
  String key = 'k',
  String source = 'booking',
  String? status = 'confirmed',
  String? time,
  int bandId = 1,
  String bandName = 'Band',
  bool isCancelled = false,
}) =>
    EventSummary(
      key: key,
      title: 't',
      date: '2026-05-02',
      time: time,
      eventSource: source,
      status: status,
      band: BandSummary(id: bandId, name: bandName, isOwner: false),
      isCancelled: isCancelled,
    );

Widget _wrap(Widget child) => CupertinoApp(home: Center(child: child));

void main() {
  group('CalendarDayMarkers', () {
    testWidgets('renders one BandAvatar for one event', (tester) async {
      await tester.pumpWidget(_wrap(
          CalendarDayMarkers(events: [_evt()])));

      expect(find.byType(BandAvatar), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('renders two BandAvatars for two events', (tester) async {
      await tester.pumpWidget(_wrap(CalendarDayMarkers(events: [
        _evt(key: 'a', bandId: 1, bandName: 'A'),
        _evt(key: 'b', bandId: 2, bandName: 'B'),
      ])));

      expect(find.byType(BandAvatar), findsNWidgets(2));
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('renders one avatar + "+N" pill for three events',
        (tester) async {
      await tester.pumpWidget(_wrap(CalendarDayMarkers(events: [
        _evt(key: 'a', bandId: 1, bandName: 'A'),
        _evt(key: 'b', bandId: 2, bandName: 'B'),
        _evt(key: 'c', bandId: 3, bandName: 'C'),
      ])));

      expect(find.byType(BandAvatar), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('renders one avatar + "+N" pill for five events',
        (tester) async {
      await tester.pumpWidget(_wrap(CalendarDayMarkers(events: [
        for (var i = 0; i < 5; i++)
          _evt(key: 'k$i', bandId: i, bandName: 'B$i'),
      ])));

      expect(find.byType(BandAvatar), findsOneWidget);
      expect(find.text('+4'), findsOneWidget);
    });

    testWidgets('renders nothing for empty events list', (tester) async {
      await tester.pumpWidget(_wrap(const CalendarDayMarkers(events: [])));

      expect(find.byType(BandAvatar), findsNothing);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('orders by event time, nulls last', (tester) async {
      // Three events: '20:00', null, '08:00'.
      // Rendered order should be: '08:00', '20:00', then null (in "+N").
      // With two avatars before "+N", the visible avatars should be the two
      // with times — in time order — and the null event lives in the +1 pill.
      await tester.pumpWidget(_wrap(CalendarDayMarkers(events: [
        _evt(key: 'late', time: '20:00', bandId: 1, bandName: 'Late'),
        _evt(key: 'no-time', time: null, bandId: 2, bandName: 'NoTime'),
        _evt(key: 'early', time: '08:00', bandId: 3, bandName: 'Early'),
      ])));

      // 3 events → 1 avatar + "+2" pill. Avatar must be the earliest-time one.
      expect(find.byType(BandAvatar), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      // The avatar shown is the "Early" band's first letter ("E").
      expect(find.text('E'), findsOneWidget);
    });
  });

  group('CalendarEventMarker', () {
    testWidgets('renders a BandAvatar', (tester) async {
      await tester.pumpWidget(_wrap(CalendarEventMarker(event: _evt())));
      expect(find.byType(BandAvatar), findsOneWidget);
    });

    testWidgets('uses CustomPaint for dashed ring when booking is pending',
        (tester) async {
      await tester.pumpWidget(_wrap(
          CalendarEventMarker(event: _evt(status: 'pending'))));

      // The dashed ring is drawn via a CustomPaint with our painter.
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('cancelled booking fades the avatar to 40% opacity',
        (tester) async {
      await tester.pumpWidget(_wrap(
          CalendarEventMarker(event: _evt(status: 'cancelled'))));

      // The marker wraps its avatar in an Opacity with 0.4 alpha when cancelled.
      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 0.4);
    });

    testWidgets('non-cancelled booking renders the avatar at full opacity',
        (tester) async {
      await tester.pumpWidget(_wrap(
          CalendarEventMarker(event: _evt(status: 'confirmed'))));

      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 1.0);
    });

    testWidgets('renders without crashing when event.band is null',
        (tester) async {
      const eventNoBand = EventSummary(
        key: 'no-band',
        title: 'Legacy Event',
        date: '2026-05-02',
        eventSource: 'band_event',
      );

      await tester.pumpWidget(_wrap(const CalendarEventMarker(event: eventNoBand)));

      // Avatar is replaced by a SizedBox placeholder, so no BandAvatar is rendered
      // — but the marker still renders (no crash, ring is still drawn).
      expect(find.byType(BandAvatar), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('cancelled rehearsal marker fades avatar and announces cancelled',
        (tester) async {
      final handle = tester.ensureSemantics();
      const eventRehearsalCancelled = EventSummary(
        key: 'evt-1',
        title: 'Tuesday Rehearsal',
        date: '2026-07-20',
        eventSource: 'rehearsal',
        isCancelled: true,
      );
      await tester.pumpWidget(_wrap(const CalendarEventMarker(event: eventRehearsalCancelled)));

      expect(find.bySemanticsLabel('Event rehearsal, cancelled'), findsOneWidget);

      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 0.4);

      handle.dispose();
    });

    testWidgets('active rehearsal marker keeps full opacity and plain label',
        (tester) async {
      final handle = tester.ensureSemantics();
      const eventRehearsalActive = EventSummary(
        key: 'evt-1',
        title: 'Tuesday Rehearsal',
        date: '2026-07-20',
        eventSource: 'rehearsal',
      );
      await tester.pumpWidget(_wrap(const CalendarEventMarker(event: eventRehearsalActive)));

      expect(find.bySemanticsLabel('Event rehearsal'), findsOneWidget);

      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 1.0);

      handle.dispose();
    });
  });
}
