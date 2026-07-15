import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/widgets/calendar_event_marker.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

void main() {
  EventSummary rehearsal({bool cancelled = false}) => EventSummary(
        key: 'evt-1',
        title: 'Tuesday Rehearsal',
        date: '2026-07-20',
        eventSource: 'rehearsal',
        isCancelled: cancelled,
      );

  Future<void> pump(WidgetTester tester, EventSummary event) => tester.pumpWidget(
        CupertinoApp(
          home: Center(child: CalendarEventMarker(event: event)),
        ),
      );

  testWidgets('cancelled rehearsal marker fades avatar and announces cancelled',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, rehearsal(cancelled: true));

    expect(find.bySemanticsLabel('Event rehearsal, cancelled'), findsOneWidget);

    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 0.4);

    handle.dispose();
  });

  testWidgets('active rehearsal marker keeps full opacity and plain label',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, rehearsal());

    expect(find.bySemanticsLabel('Event rehearsal'), findsOneWidget);

    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 1.0);

    handle.dispose();
  });
}
