import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';
import 'package:tts_bandmate/features/songs/screens/song_list_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com');

class _StubAuth extends AuthNotifier {
  _StubAuth(this._bands);
  final List<BandSummary> _bands;
  @override
  Future<AuthState> build() async => AuthAuthenticated(user: _user, bands: _bands);
}

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeRepo implements SongsRepository {
  _FakeRepo(this._songs);
  final List<Song> _songs;
  int? lastDeletedSongId;

  @override
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async =>
      (songs: _songs, genres: const <String>[]);

  @override
  Future<void> deleteSong(int bandId, int songId) async {
    lastDeletedSongId = songId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _harness(_FakeRepo repo, {bool owner = true}) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const SongListScreen()),
  ]);
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(
          () => _StubAuth([BandSummary(id: 1, name: 'Band', isOwner: owner)])),
      selectedBandProvider.overrideWith(_StubBand.new),
      songsRepositoryProvider.overrideWithValue(repo),
    ],
    child: CupertinoApp.router(routerConfig: router),
  );
}

const _songs = [
  Song(id: 1, bandId: 1, title: 'Caravan', artist: 'Ellington'),
  Song(id: 2, bandId: 1, title: 'Autumn Leaves'),
  Song(id: 3, bandId: 1, title: 'Retired Tune', active: false),
];

void main() {
  testWidgets('renders active songs alphabetised and hides inactive by default',
      (tester) async {
    await tester.pumpWidget(_harness(_FakeRepo(_songs)));
    await tester.pumpAndSettle();

    expect(find.text('Autumn Leaves'), findsOneWidget);
    expect(find.text('Caravan'), findsOneWidget);
    expect(find.text('Retired Tune'), findsNothing);
  });

  testWidgets('inactive toggle reveals inactive songs', (tester) async {
    await tester.pumpWidget(_harness(_FakeRepo(_songs)));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Show inactive songs'));
    await tester.pumpAndSettle();

    expect(find.text('Retired Tune'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
  });

  testWidgets('search filters by title and artist', (tester) async {
    await tester.pumpWidget(_harness(_FakeRepo(_songs)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoSearchTextField), 'elling');
    await tester.pumpAndSettle();

    expect(find.text('Caravan'), findsOneWidget);
    expect(find.text('Autumn Leaves'), findsNothing);
  });

  testWidgets('owner long-press shows the delete confirmation and deletes',
      (tester) async {
    final repo = _FakeRepo(_songs);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Caravan'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Song'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repo.lastDeletedSongId, 1);
    expect(find.text('Caravan'), findsNothing);
  });

  testWidgets('non-owner long-press does nothing', (tester) async {
    await tester.pumpWidget(_harness(_FakeRepo(_songs), owner: false));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Caravan'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Song'), findsNothing);
  });

  testWidgets('empty band shows the empty state', (tester) async {
    await tester.pumpWidget(_harness(_FakeRepo(const [])));
    await tester.pumpAndSettle();

    expect(find.text('No songs yet'), findsOneWidget);
  });
}
