import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/library/providers/library_filter_provider.dart';
import 'package:tts_bandmate/features/library/widgets/library_filter_button.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: CupertinoApp(home: CupertinoPageScaffold(child: child)),
    );

void main() {
  testWidgets('inactive: icon visible, no badge', (tester) async {
    await tester.pumpWidget(_wrap(LibraryFilterButton(onPressed: () {})));
    expect(find.byIcon(CupertinoIcons.line_horizontal_3_decrease), findsOneWidget);
    // Badge is a Text inside a circular Container; "1" should NOT be present.
    expect(find.text('1'), findsNothing);
  });

  testWidgets('active: badge shows hidden-band count', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Pre-toggle two bands so the button shows "2".
    container.read(libraryFilterProvider.notifier).toggleBand(1);
    container.read(libraryFilterProvider.notifier).toggleBand(2);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: LibraryFilterButton(onPressed: () {}),
        ),
      ),
    ));
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('tap fires onPressed', (tester) async {
    var fired = false;
    await tester.pumpWidget(
      _wrap(LibraryFilterButton(onPressed: () => fired = true)),
    );
    await tester.tap(find.byIcon(CupertinoIcons.line_horizontal_3_decrease));
    expect(fired, true);
  });
}
