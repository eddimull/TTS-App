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

  testWidgets('title field keeps the cursor at the end after a parent rebuild',
      (tester) async {
    // Reproduces the iOS bug: each keystroke triggered a parent setState
    // that rebuilt the card. The card built a fresh TextEditingController
    // inline, whose cursor defaults to offset 0 — so the next keystroke
    // inserted at the front, turning "abcdef" into "fedcba".
    EventDraft draft = const EventDraft(title: '', date: '2026-06-13');

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => CupertinoApp(
          home: Center(
            child: EventSubFormCard(
              draft: draft,
              canDelete: true,
              onChange: (newDraft) => setState(() => draft = newDraft),
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    final titleField = find.byType(CupertinoTextField).first;

    // Type a character; the parent rebuilds the card via setState.
    await tester.enterText(titleField, 'abc');
    await tester.pump();

    // After the rebuild the field's controller must still hold the text
    // with the cursor at the end. A freshly-constructed controller would
    // reset selection to offset 0, which is the bug.
    final controller = tester.widget<CupertinoTextField>(titleField).controller!;
    expect(controller.text, 'abc');
    expect(controller.selection.baseOffset, 3,
        reason: 'cursor must stay at the end of the text after a rebuild');
  });
}
