import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';
import 'package:tts_bandmate/features/songs/screens/song_detail_screen.dart';
import 'package:tts_bandmate/features/songs/screens/song_form_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

/// Mirrors the `/songs/:songId/edit` route builder in
/// lib/core/config/router.dart: when `state.extra` is a [Song] it opens the
/// form pre-filled; otherwise (deep link / restored navigation with no
/// payload) it must gracefully fall back to [SongDetailScreen] instead of
/// crashing on a hard `as Song` cast.
Widget _editRouteBuilder(BuildContext _, GoRouterState state) {
  final extra = state.extra;
  if (extra is Song) {
    return SongFormScreen(existing: extra);
  }
  return SongDetailScreen(
    songId: int.parse(state.pathParameters['songId']!),
  );
}

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeRepo implements SongsRepository {
  @override
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async =>
      (
        songs: const [Song(id: 7, bandId: 1, title: 'Old Title')],
        genres: const <String>[],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _harness({required String location}) {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/songs/:songId/edit', builder: _editRouteBuilder),
    ],
  );
  return ProviderScope(
    overrides: [
      selectedBandProvider.overrideWith(_StubBand.new),
      songsRepositoryProvider.overrideWithValue(_FakeRepo()),
    ],
    child: CupertinoApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets(
      'edit route with no Song extra (deep link) falls back to the detail '
      'screen instead of crashing', (tester) async {
    await tester.pumpWidget(_harness(location: '/songs/7/edit'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SongDetailScreen), findsOneWidget);
    expect(find.byType(SongFormScreen), findsNothing);
    expect(find.text('Old Title'), findsOneWidget);
  });
}
