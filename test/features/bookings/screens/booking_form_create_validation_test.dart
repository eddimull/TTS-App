import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_type.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/bookings/screens/booking_form_screen.dart';

// Create-mode validation: the backend requires a start time on every event,
// so the form must block submission and show a clear message rather than
// firing a request that returns a raw 422.

Future<void> _pumpCreateForm(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Stub event types so the screen doesn't hit the network.
        eventTypesProvider.overrideWith(
          (_) async => [const EventType(id: 1, name: 'Concert')],
        ),
      ],
      child: const CupertinoApp(
        home: BookingFormScreen(bandId: 1, existing: null),
      ),
    ),
  );
  // Let eventTypesProvider resolve.
  await tester.pump();
}

void main() {
  testWidgets('save is blocked with a message when an event has no start time',
      (tester) async {
    await _pumpCreateForm(tester);

    // A fresh create form starts with one event row that has a date but no
    // start time. Provide a booking name so name validation passes first —
    // the name field is the first text-entry widget on the screen.
    await tester.enterText(
        find.byType(EditableText).first, 'Summer Festival');
    await tester.pumpAndSettle();

    // Select an event type (picker defaults to the first entry, "Concert"),
    // so the event-type check passes and the start-time check is reached.
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Tap the save button.
    final saveButton = find.text('Save Booking');
    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // The start-time requirement is surfaced inline (at the bottom of the
    // scrollable form); no request was sent.
    await tester.scrollUntilVisible(
      find.textContaining('start time'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('start time'), findsOneWidget);
  });

  testWidgets('start time picker row shows the Required placeholder',
      (tester) async {
    await _pumpCreateForm(tester);

    // The start-time row on a fresh event signals that it must be filled.
    expect(find.text('Required'), findsWidgets);
  });
}
