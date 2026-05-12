import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/services/booking_save_orchestrator.dart';
import 'package:tts_bandmate/features/bookings/widgets/booking_save_button.dart';

void main() {
  testWidgets('pristine state shows "Save Booking"', (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          trailing: BookingSaveButton(
            isSaving: false,
            lastResult: null,
            onPressed: () {},
          ),
        ),
        child: const SizedBox.shrink(),
      ),
    ));
    expect(find.text('Save Booking'), findsOneWidget);
    expect(find.textContaining('Retry'), findsNothing);
  });

  testWidgets('partial failure shows "Retry Failed (N)"', (tester) async {
    final result = BookingSaveResult(
      bookingPatch: const OperationSuccess(),
      eventUpdates: {
        'evt_1': const OperationFailure('boom'),
        'evt_2': const OperationFailure('boom'),
      },
      eventCreates: const {},
      eventDeletes: const {},
    );
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          trailing: BookingSaveButton(
            isSaving: false,
            lastResult: result,
            onPressed: () {},
          ),
        ),
        child: const SizedBox.shrink(),
      ),
    ));
    expect(find.text('Retry Failed (2)'), findsOneWidget);
  });
}
