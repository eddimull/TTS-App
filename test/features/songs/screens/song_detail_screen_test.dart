import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';
import 'package:tts_bandmate/features/songs/screens/song_detail_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeRepo implements SongsRepository {
  _FakeRepo(this._songs);
  final List<Song> _songs;

  @override
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async =>
      (songs: _songs, genres: const <String>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

String? pushedChartLocation;
Object? pushedChartExtra;

Widget _harness(List<Song> songs, {int songId = 7}) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => SongDetailScreen(songId: songId)),
    GoRoute(
      path: '/library/:chartId',
      builder: (_, state) {
        pushedChartLocation = state.uri.path;
        pushedChartExtra = state.extra;
        return const CupertinoPageScaffold(child: Text('chart detail'));
      },
    ),
  ]);
  return ProviderScope(
    overrides: [
      selectedBandProvider.overrideWith(_StubBand.new),
      songsRepositoryProvider.overrideWithValue(_FakeRepo(songs)),
    ],
    child: CupertinoApp.router(routerConfig: router),
  );
}

const _song = Song(
  id: 7,
  bandId: 2,
  title: 'September',
  artist: 'Earth, Wind & Fire',
  songKey: 'A',
  genre: 'Funk',
  bpm: 126,
  notes: 'Watch the horn break',
  rating: 9,
  energy: 10,
  leadSinger: SongLeadSinger(id: 3, displayName: 'Alex'),
  transitionSong: SongRef(id: 9, title: 'Boogie Wonderland'),
  charts: [SongChartSummary(id: 11, title: 'September - Horns')],
);

void main() {
  setUp(() {
    pushedChartLocation = null;
    pushedChartExtra = null;
  });

  testWidgets('renders every populated field', (tester) async {
    await tester.pumpWidget(_harness(const [_song]));
    await tester.pumpAndSettle();

    expect(find.text('September'), findsOneWidget);
    expect(find.text('Earth, Wind & Fire'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('Funk'), findsOneWidget);
    expect(find.text('126'), findsOneWidget);
    expect(find.text('9 / 10'), findsOneWidget);
    expect(find.text('10 / 10'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Boogie Wonderland'), findsOneWidget);
    expect(find.text('Watch the horn break'), findsOneWidget);
    expect(find.text('SHEET MUSIC'), findsOneWidget);
    expect(find.text('September - Horns'), findsOneWidget);
  });

  testWidgets('tapping a linked chart pushes the chart detail route',
      (tester) async {
    await tester.pumpWidget(_harness(const [_song]));
    await tester.pumpAndSettle();

    // The chart row sits below the fold under the detail card's rows; the
    // ListView unbuilds off-screen content, so scroll it into view first.
    await tester.scrollUntilVisible(
      find.text('September - Horns'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('September - Horns'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('September - Horns'));
    await tester.pumpAndSettle();

    expect(pushedChartLocation, '/library/11');
    expect(pushedChartExtra, 2); // the song's bandId
  });

  testWidgets('unknown song id shows a not-found state', (tester) async {
    await tester.pumpWidget(_harness(const [_song], songId: 999));
    await tester.pumpAndSettle();

    expect(find.text('Song not found'), findsOneWidget);
  });
}
