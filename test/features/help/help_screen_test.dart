import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/help/providers/help_providers.dart';
import 'package:tts_bandmate/features/help/screens/help_screen.dart';
import 'fake_help_repository.dart';

void main() {
  testWidgets('HelpScreen shows category labels and article titles',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          helpRepositoryProvider.overrideWithValue(FakeHelpRepository()),
        ],
        child: const CupertinoApp(
          home: HelpScreen(),
        ),
      ),
    );

    // Initial frame: loading state.
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    // "Getting started" article rendered as a tappable card.
    expect(find.text('You created a band'), findsOneWidget);

    // Remaining category section header + its article row.
    expect(find.text('FAQ'), findsOneWidget);
    expect(find.text('How do payouts work?'), findsOneWidget);

    // Long titles must wrap, not overflow, at 320pt width.
    expect(
      find.text('How does the live setlist work during a performance?'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
