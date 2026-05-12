import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_draft.dart';
import 'package:tts_bandmate/features/bookings/widgets/event_sub_form_card.dart';

void main() {
  testWidgets('renders inline error when saveError non-null', (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: Center(
        child: EventSubFormCard(
          draft: const EventDraft(title: 'X', date: '2026-06-13'),
          canDelete: true,
          saveError: 'Server error',
          onChange: (_) {},
          onDelete: () {},
        ),
      ),
    ));
    expect(find.text('Save failed — tap to retry'), findsOneWidget);
  });

  testWidgets('does not render error when saveError null', (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: Center(
        child: EventSubFormCard(
          draft: const EventDraft(title: 'X', date: '2026-06-13'),
          canDelete: true,
          onChange: (_) {},
          onDelete: () {},
        ),
      ),
    ));
    expect(find.text('Save failed — tap to retry'), findsNothing);
  });

  testWidgets('delete button disabled when canDelete is false',
      (tester) async {
    var deleteCalled = false;
    await tester.pumpWidget(CupertinoApp(
      home: Center(
        child: EventSubFormCard(
          draft: const EventDraft(title: 'X', date: '2026-06-13'),
          canDelete: false,
          onChange: (_) {},
          onDelete: () => deleteCalled = true,
        ),
      ),
    ));
    final btn = find.byIcon(CupertinoIcons.trash);
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    await tester.pump();
    expect(deleteCalled, isFalse);
  });

  testWidgets('onRetryRow fires when tapping the inline error',
      (tester) async {
    var retryCalled = false;
    await tester.pumpWidget(CupertinoApp(
      home: Center(
        child: EventSubFormCard(
          draft: const EventDraft(title: 'X', date: '2026-06-13'),
          canDelete: true,
          saveError: 'Server error',
          onChange: (_) {},
          onDelete: () {},
          onRetryRow: () => retryCalled = true,
        ),
      ),
    ));
    await tester.tap(find.text('Save failed — tap to retry'));
    await tester.pump();
    expect(retryCalled, isTrue);
  });
}
