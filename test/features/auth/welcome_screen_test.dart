import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/screens/welcome_screen.dart';

void main() {
  Future<void> pumpAt(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(const CupertinoApp(home: WelcomeScreen()));
    await t.pump();
  }

  testWidgets('carousel preview is vertically centered on tall screens',
      (t) async {
    await pumpAt(t, const Size(390, 844));

    // Proxies for the preview card's vertical extent (first panel).
    final previewTop = t.getTopLeft(find.text('NOW PLAYING')).dy;
    final previewBottom =
        t.getBottomLeft(find.text('Uptown Funk · Bruno Mars')).dy;
    final previewCenter = (previewTop + previewBottom) / 2;

    // The area the preview should center within: below the header, above the
    // panel title.
    final areaTop = t.getBottomLeft(find.text('Bandmate')).dy;
    final areaBottom = t.getTopLeft(find.text('Run the night, live')).dy;
    final areaCenter = (areaTop + areaBottom) / 2;

    expect(
      previewCenter,
      closeTo(areaCenter, 40),
      reason: 'preview card should be vertically centered, not pinned to the '
          'top of the carousel area',
    );
  });

  testWidgets('short screens scroll the preview instead of overflowing',
      (t) async {
    await pumpAt(t, const Size(320, 480));
    expect(t.takeException(), isNull);
    expect(find.text('NOW PLAYING'), findsOneWidget);
  });
}
