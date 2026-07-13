import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/library/data/library_repository.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';
import 'package:tts_bandmate/features/library/screens/chart_detail_screen.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';
import 'package:tts_bandmate/features/songs/providers/songs_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

Chart _chart({ChartSongRef? song}) => Chart(
      id: 10,
      bandId: 1,
      title: 'Higher Ground Lead Sheet',
      composer: '',
      description: '',
      price: 0,
      isPublic: false,
      uploadsCount: 0,
      uploads: const [],
      song: song,
    );

/// Fake repo whose getChart() reflects whatever updateChartSong() last set,
/// so re-reading chartDetailProvider after invalidation shows the new link.
class _FakeLibraryRepo implements LibraryRepository {
  _FakeLibraryRepo(this._chart);
  Chart _chart;
  bool shouldFailUpdate = false;

  @override
  Future<Chart> getChart(int bandId, int chartId) async => _chart;

  @override
  Future<Chart> updateChartSong(
    int bandId,
    int chartId, {
    required int? songId,
  }) async {
    if (shouldFailUpdate) {
      // A Dio error with a response body — friendlyMessage() should surface
      // its 'message' field instead of the raw exception toString().
      throw DioException(
        requestOptions: RequestOptions(path: '/mobile/bands/1/charts/10'),
        response: Response(
          requestOptions: RequestOptions(path: '/mobile/bands/1/charts/10'),
          statusCode: 422,
          data: {'message': 'That song already has a linked chart.'},
        ),
      );
    }
    _chart = Chart(
      id: _chart.id,
      bandId: _chart.bandId,
      title: _chart.title,
      composer: _chart.composer,
      description: _chart.description,
      price: _chart.price,
      isPublic: _chart.isPublic,
      uploadsCount: _chart.uploadsCount,
      uploads: _chart.uploads,
      song: songId != null ? const ChartSongRef(id: 5, title: 'Higher Ground') : null,
    );
    return _chart;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Spies on getSongs() calls so tests can assert songsProvider rebuilds
/// (i.e. was invalidated) after a chart-song link change.
class _FakeSongsRepo implements SongsRepository {
  int getSongsCallCount = 0;

  @override
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async {
    getSongsCallCount++;
    return (
      songs: const [Song(id: 5, bandId: 1, title: 'Higher Ground', artist: 'Stevie')],
      genres: const <String>[],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

Widget _harness(_FakeLibraryRepo libraryRepo, _FakeSongsRepo songsRepo) =>
    ProviderScope(
      overrides: [
        selectedBandProvider.overrideWith(_StubBand.new),
        libraryRepositoryProvider.overrideWithValue(libraryRepo),
        songsRepositoryProvider.overrideWithValue(songsRepo),
      ],
      child: const CupertinoApp(
        home: ChartDetailScreen(bandId: 1, chartId: 10),
      ),
    );

void main() {
  testWidgets('linking a song invalidates songsProvider so it rebuilds',
      (tester) async {
    final libraryRepo = _FakeLibraryRepo(_chart());
    final songsRepo = _FakeSongsRepo();

    await tester.pumpWidget(_harness(libraryRepo, songsRepo));
    await tester.pumpAndSettle();

    // Prime songsProvider once, as a real screen watching it would.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChartDetailScreen)),
    );
    await container.read(songsProvider.future);
    final countBeforeLink = songsRepo.getSongsCallCount;
    expect(countBeforeLink, greaterThanOrEqualTo(1));

    expect(find.text('None — tap to link a song'), findsOneWidget);

    await tester.tap(find.text('None — tap to link a song'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Higher Ground — Stevie'));
    await tester.pumpAndSettle();

    // The link succeeded and chartDetailProvider reflects it — the linked
    // song editor row no longer shows the placeholder.
    expect(find.text('None — tap to link a song'), findsNothing);

    // songsProvider was invalidated by the link change; reading it again
    // triggers a rebuild (another getSongs() call beyond whatever the
    // picker sheet's own bandSongsProvider lookup added).
    final countAfterPickerOpen = songsRepo.getSongsCallCount;
    await container.read(songsProvider.future);
    expect(songsRepo.getSongsCallCount, countAfterPickerOpen + 1);
  });

  testWidgets('relink failure shows a friendly error dialog, not e.toString()',
      (tester) async {
    final libraryRepo = _FakeLibraryRepo(_chart())..shouldFailUpdate = true;
    final songsRepo = _FakeSongsRepo();

    await tester.pumpWidget(_harness(libraryRepo, songsRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('None — tap to link a song'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Higher Ground — Stevie'));
    await tester.pumpAndSettle();

    expect(find.text('Could Not Update Link'), findsOneWidget);
    expect(
        find.text('That song already has a linked chart.'), findsOneWidget);
    // Not the raw DioException.toString() dump.
    expect(find.textContaining('DioException'), findsNothing);
  });
}
