import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/library/screens/create_chart_screen.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';

const _band = BandSummary(id: 2, name: 'The Testers', isOwner: true);

const _song = Song(
  id: 7,
  bandId: 2,
  title: 'September',
  artist: 'Earth, Wind & Fire',
  songKey: 'A',
  genre: 'Funk',
  bpm: 126,
  notes: '',
  active: true,
);

Widget _harness({Song? initialSong}) => ProviderScope(
      child: CupertinoApp(
        home: CreateChartScreen(band: _band, initialSong: initialSong),
      ),
    );

void main() {
  testWidgets('prefills title, composer, and linked song from initialSong',
      (tester) async {
    await tester.pumpWidget(_harness(initialSong: _song));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(CupertinoTextField, 'September'),
        findsOneWidget);
    expect(find.widgetWithText(CupertinoTextField, 'Earth, Wind & Fire'),
        findsOneWidget);
    // The linked-song row shows the preset song.
    expect(find.text('September'), findsWidgets);
  });

  testWidgets('without initialSong the form starts empty', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('September'), findsNothing);
  });
}
