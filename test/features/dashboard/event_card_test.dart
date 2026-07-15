import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/widgets/event_card.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

void main() {
  EventSummary event({int unread = 0}) => EventSummary(
        key: 'evt-1',
        title: 'Tuesday Rehearsal',
        date: '2026-07-20',
        eventSource: 'rehearsal',
        unreadCommentCount: unread,
      );

  testWidgets('shows 💬 badge with count when there are unread comments',
      (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(child: EventCard(event: event(unread: 3))),
    ));

    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.chat_bubble_fill), findsOneWidget);
  });

  testWidgets('hides the badge when there are no unread comments',
      (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(child: EventCard(event: event())),
    ));

    expect(find.byIcon(CupertinoIcons.chat_bubble_fill), findsNothing);
  });
}
