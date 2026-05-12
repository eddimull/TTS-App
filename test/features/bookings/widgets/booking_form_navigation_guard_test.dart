import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/services/booking_save_orchestrator.dart';
import 'package:tts_bandmate/features/bookings/widgets/booking_form_navigation_guard.dart';

void main() {
  testWidgets('returns true immediately when result is null', (tester) async {
    late bool outcome;
    await tester.pumpWidget(CupertinoApp(
      home: Builder(
        builder: (ctx) => CupertinoButton(
          child: const Text('Try Leave'),
          onPressed: () async {
            outcome =
                await BookingFormNavigationGuard.shouldAllowLeave(ctx, null);
          },
        ),
      ),
    ));
    await tester.tap(find.text('Try Leave'));
    await tester.pumpAndSettle();
    expect(outcome, isTrue);
  });

  testWidgets('shows alert and returns true on Discard', (tester) async {
    late bool outcome;
    final result = BookingSaveResult(
      bookingPatch: const OperationSuccess(),
      eventUpdates: {'evt_1': const OperationFailure('boom')},
      eventCreates: const {},
      eventDeletes: const {},
    );
    await tester.pumpWidget(CupertinoApp(
      home: Builder(
        builder: (ctx) => CupertinoButton(
          child: const Text('Try Leave'),
          onPressed: () async {
            outcome = await BookingFormNavigationGuard.shouldAllowLeave(
                ctx, result);
          },
        ),
      ),
    ));
    await tester.tap(find.text('Try Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(find.textContaining('1 still failed'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(outcome, isTrue);
  });

  testWidgets('returns false on Stay & Retry', (tester) async {
    late bool outcome;
    final result = BookingSaveResult(
      bookingPatch: const OperationFailure('boom'),
      eventUpdates: const {},
      eventCreates: const {},
      eventDeletes: const {},
    );
    await tester.pumpWidget(CupertinoApp(
      home: Builder(
        builder: (ctx) => CupertinoButton(
          child: const Text('Try Leave'),
          onPressed: () async {
            outcome = await BookingFormNavigationGuard.shouldAllowLeave(
                ctx, result);
          },
        ),
      ),
    ));
    await tester.tap(find.text('Try Leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stay & Retry'));
    await tester.pumpAndSettle();
    expect(outcome, isFalse);
  });
}
