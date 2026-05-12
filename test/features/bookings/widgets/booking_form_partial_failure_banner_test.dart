import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/widgets/booking_form_partial_failure_banner.dart';

void main() {
  testWidgets('renders the spec copy', (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: BookingFormPartialFailureBanner(onDismiss: () {}),
    ));
    expect(find.text('No changes saved — check your connection'),
        findsOneWidget);
  });

  testWidgets('tap fires onDismiss', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(CupertinoApp(
      home: BookingFormPartialFailureBanner(onDismiss: () => dismissed = true),
    ));
    await tester.tap(find.byType(BookingFormPartialFailureBanner));
    expect(dismissed, isTrue);
  });
}
