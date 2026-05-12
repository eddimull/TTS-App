import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/widgets/part_of_booking_row.dart';

void main() {
  group('PartOfBookingRow', () {
    testWidgets('renders "Part of: " label and booking name', (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: PartOfBookingRow(
              bookingName: 'Symphony Hire',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Part of: '), findsOneWidget);
      expect(find.text('Symphony Hire'), findsOneWidget);
    });

    testWidgets('fires onTap when tapped', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: PartOfBookingRow(
              bookingName: 'Summer Festival',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PartOfBookingRow));
      expect(tapped, isTrue);
    });

    testWidgets('displays a bookmark icon', (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: PartOfBookingRow(
              bookingName: 'Jazz Night',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(CupertinoIcons.bookmark), findsOneWidget);
    });
  });
}
