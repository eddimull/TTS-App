import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/dashboard/providers/calendar_filter_provider.dart';
import 'package:tts_bandmate/features/dashboard/widgets/calendar_filter_sheet.dart';

const _bandA = BandSummary(id: 1, name: 'Alpha', isOwner: true);
const _bandB = BandSummary(id: 2, name: 'Bravo', isOwner: false);

Widget _hostWith(ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: CupertinoPageScaffold(
          child: CalendarFilterSheet(bands: [_bandA, _bandB]),
        ),
      ),
    );

void main() {
  group('CalendarFilterSheet', () {
    testWidgets('renders all bands and three event-type switches',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostWith(container));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('Performances'), findsOneWidget);
      expect(find.text('Rehearsals'), findsOneWidget);
      expect(find.text('Other Events'), findsOneWidget);
    });

    testWidgets('hides Clear All when no filters active', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostWith(container));
      await tester.pumpAndSettle();

      expect(find.text('Clear All'), findsNothing);
    });

    testWidgets('shows Clear All when filters active and clears on tap',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(calendarFilterProvider.notifier).toggleBand(1);

      await tester.pumpWidget(_hostWith(container));
      await tester.pumpAndSettle();

      expect(find.text('Clear All'), findsOneWidget);

      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();

      expect(container.read(calendarFilterProvider).isActive, false);
      expect(find.text('Clear All'), findsNothing);
    });

    testWidgets('tapping a band chip toggles its hidden state',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostWith(container));
      await tester.pumpAndSettle();

      // Initially nothing hidden.
      expect(container.read(calendarFilterProvider).hiddenBandIds, isEmpty);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(container.read(calendarFilterProvider).hiddenBandIds, {1});

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(container.read(calendarFilterProvider).hiddenBandIds, isEmpty);
    });

    testWidgets('toggling Performances switch hides booking source',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostWith(container));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(Row, 'Performances')
          .evaluate()
          .isNotEmpty
          ? find.byType(CupertinoSwitch).first
          : find.byType(CupertinoSwitch).first);
      await tester.pumpAndSettle();

      expect(container.read(calendarFilterProvider).hiddenEventTypes,
          contains('booking'));
    });
  });
}
