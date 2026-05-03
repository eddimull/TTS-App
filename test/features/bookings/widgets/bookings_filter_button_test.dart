import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_status.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_filter_provider.dart';
import 'package:tts_bandmate/features/bookings/widgets/bookings_filter_button.dart';

void main() {
  testWidgets('renders no badge when no filter is active', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: Center(
              child: BookingsFilterButton(onPressed: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // No badge text rendered.
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('shows badge with active count', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(bookingsFilterProvider.notifier)
        .setStatus(BookingStatus.confirmed);
    container.read(bookingsFilterProvider.notifier).toggleBand(7);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(
            child: BookingsFilterButton(onPressed: () {}),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('invokes onPressed when tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: Center(
              child: BookingsFilterButton(onPressed: () => taps++),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(BookingsFilterButton));
    expect(taps, 1);
  });
}
