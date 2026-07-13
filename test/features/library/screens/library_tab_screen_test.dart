import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/library/data/library_repository.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';
import 'package:tts_bandmate/features/library/screens/library_tab_screen.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com');
const _band = BandSummary(id: 1, name: 'Band A', isOwner: true);

class _StubAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async =>
      const AuthAuthenticated(user: _user, bands: [_band]);
}

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeSongsRepo implements SongsRepository {
  @override
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async =>
      (
        songs: const [Song(id: 1, bandId: 1, title: 'My Song')],
        genres: const <String>[],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeLibraryRepo implements LibraryRepository {
  @override
  Future<List<Chart>> getAllCharts() async => const [
        Chart(
          id: 1,
          bandId: 1,
          title: 'My Chart',
          composer: '',
          description: '',
          price: 0,
          isPublic: false,
          uploadsCount: 0,
          uploads: [],
          band: ChartBand(id: 1, name: 'Band A', isPersonal: false),
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _harness() {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const LibraryTabScreen()),
  ]);
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(_StubAuth.new),
      selectedBandProvider.overrideWith(_StubBand.new),
      songsRepositoryProvider.overrideWithValue(_FakeSongsRepo()),
      libraryRepositoryProvider.overrideWithValue(_FakeLibraryRepo()),
    ],
    child: CupertinoApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('shows both segments and defaults to Song list', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // 'Song list' appears in both the segment and the embedded screen's nav
    // bar (which can render large + collapsed title Texts) — use findsWidgets.
    expect(find.text('Song list'), findsWidgets);
    expect(find.text('Sheet music'), findsOneWidget);
    expect(find.text('My Song'), findsOneWidget);
    expect(find.text('My Chart'), findsNothing);
  });

  testWidgets('switching to Sheet music renders the library screen',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sheet music'));
    await tester.pumpAndSettle();

    expect(find.text('My Chart'), findsOneWidget);
    expect(find.text('My Song'), findsNothing);
  });
}
