import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/providers/calendar_filter_provider.dart';
import 'package:tts_bandmate/features/dashboard/widgets/calendar_filter_button.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: CupertinoApp(home: Center(child: child)),
    );

void main() {
  group('CalendarFilterButton', () {
    testWidgets('renders without badge when no filters active',
        (tester) async {
      await tester.pumpWidget(_wrap(
          CalendarFilterButton(onPressed: () {})));

      expect(find.byIcon(CupertinoIcons.line_horizontal_3_decrease),
          findsOneWidget);
      // No badge text when count == 0.
      expect(find.text('1'), findsNothing);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('renders badge with count when filters active',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(calendarFilterProvider.notifier);
      notifier.toggleBand(1);
      notifier.toggleEventType('rehearsal');

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          home: Center(child: CalendarFilterButton(onPressed: () {})),
        ),
      ));

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('caps badge text at 9+', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(calendarFilterProvider.notifier);
      for (var i = 0; i < 10; i++) {
        notifier.toggleBand(i);
      }

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          home: Center(child: CalendarFilterButton(onPressed: () {})),
        ),
      ));

      expect(find.text('9+'), findsOneWidget);
    });

    testWidgets('invokes onPressed when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
          CalendarFilterButton(onPressed: () => tapped = true)));

      await tester.tap(find.byType(CalendarFilterButton));
      expect(tapped, true);
    });

    testWidgets('uses tertiarySystemBackground fill when no filters active',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          home: Center(child: CalendarFilterButton(onPressed: () {})),
        ),
      ));

      // The visible circle is the inner Container with margin EdgeInsets.all(4).
      // Find it by walking down from the GestureDetector.
      final circleContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(GestureDetector),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = circleContainer.decoration as BoxDecoration;
      final element = tester.element(find.byType(CalendarFilterButton));
      expect(
        decoration.color,
        CupertinoColors.tertiarySystemBackground.resolveFrom(element),
      );
    });

    testWidgets('flips fill to systemBlue when filters active',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(calendarFilterProvider.notifier).toggleBand(1);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          home: Center(child: CalendarFilterButton(onPressed: () {})),
        ),
      ));

      final circleContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(GestureDetector),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = circleContainer.decoration as BoxDecoration;
      final element = tester.element(find.byType(CalendarFilterButton));
      expect(
        decoration.color,
        CupertinoColors.systemBlue.resolveFrom(element),
      );
    });
  });
}
