import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/library/data/library_repository.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';
import 'package:tts_bandmate/features/library/providers/library_provider.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';
import 'package:tts_bandmate/features/songs/providers/songs_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeRepo implements LibraryRepository {
  _FakeRepo({this.charts = const []});

  List<Chart> charts;
  Chart? lastCreated;
  int? lastDeletedChartId;
  int? lastPatchedChartId;
  int? lastPatchedSongId;
  bool lastPatchHadSongId = false;

  @override
  Future<List<Chart>> getAllCharts() async => charts;

  @override
  Future<Chart> createChart(
    int bandId, {
    required String title,
    String? composer,
    String? description,
    double? price,
    bool isPublic = false,
    int? songId,
  }) async {
    final newChart = Chart(
      id: 999,
      bandId: bandId,
      title: title,
      composer: composer ?? '',
      description: description ?? '',
      price: price ?? 0.0,
      isPublic: isPublic,
      uploadsCount: 0,
      uploads: const [],
      // Repo does NOT stamp band — that is the notifier's job.
      band: null,
      song: songId != null
          ? ChartSongRef(id: songId, title: 'Linked Song')
          : null,
    );
    lastCreated = newChart;
    return newChart;
  }

  @override
  Future<void> deleteChart(int bandId, int chartId) async {
    lastDeletedChartId = chartId;
  }

  @override
  Future<Chart> updateChartSong(
    int bandId,
    int chartId, {
    required int? songId,
  }) async {
    lastPatchedChartId = chartId;
    lastPatchedSongId = songId;
    lastPatchHadSongId = true;
    final existing = charts.firstWhere((c) => c.id == chartId);
    return Chart(
      id: existing.id,
      bandId: existing.bandId,
      title: existing.title,
      composer: existing.composer,
      description: existing.description,
      price: existing.price,
      isPublic: existing.isPublic,
      uploadsCount: existing.uploadsCount,
      uploads: existing.uploads,
      band: null, // repo payload does not carry the stamped band
      song: songId != null
          ? ChartSongRef(id: songId, title: 'Linked Song')
          : null,
    );
  }

  // Unused in these tests; satisfy the interface with throws.
  @override
  Future<List<Chart>> getCharts(int bandId) => throw UnimplementedError();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Spies on getSongs() calls so tests can assert songsProvider was
/// invalidated (and thus rebuilt) after a chart-song link change.
class _FakeSongsRepo implements SongsRepository {
  int getSongsCallCount = 0;

  @override
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async {
    getSongsCallCount++;
    return (songs: const <Song>[], genres: const <String>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

ProviderContainer _container(_FakeRepo repo, {_FakeSongsRepo? songsRepo}) {
  final container = ProviderContainer(overrides: [
    libraryRepositoryProvider.overrideWithValue(repo),
    songsRepositoryProvider.overrideWithValue(songsRepo ?? _FakeSongsRepo()),
    selectedBandProvider.overrideWith(_StubBand.new),
  ]);
  addTearDown(container.dispose);
  return container;
}

const _bandA = BandSummary(id: 1, name: 'Band A', isOwner: true);

void main() {
  group('LibraryNotifier.build', () {
    test('loads all charts via getAllCharts()', () async {
      final repo = _FakeRepo(charts: [
        const Chart(
          id: 10,
          bandId: 1,
          title: 'Hello',
          composer: '',
          description: '',
          price: 0,
          isPublic: false,
          uploadsCount: 0,
          uploads: [],
          band: ChartBand(id: 1, name: 'Band A', isPersonal: false),
        ),
      ]);
      final container = _container(repo);

      final state = await container.read(libraryProvider.future);
      expect(state.charts, hasLength(1));
      expect(state.charts.first.title, 'Hello');
    });
  });

  group('LibraryNotifier.createChart', () {
    test('inserts the new chart with a ChartBand stamped from the picked band',
        () async {
      final repo = _FakeRepo(charts: const []);
      final container = _container(repo);

      // Force build to complete first.
      await container.read(libraryProvider.future);

      final chart = await container
          .read(libraryProvider.notifier)
          .createChart(_bandA, title: 'Stardust');

      expect(chart.title, 'Stardust');
      expect(chart.band, isNotNull);
      expect(chart.band!.id, 1);
      expect(chart.band!.name, 'Band A');

      final state = container.read(libraryProvider).value!;
      expect(state.charts.any((c) => c.id == chart.id), true);
      expect(state.charts.firstWhere((c) => c.id == chart.id).band!.id, 1);
    });

    test('creating a chart with a linked song invalidates songsProvider',
        () async {
      final repo = _FakeRepo(charts: const []);
      final songsRepo = _FakeSongsRepo();
      final container = _container(repo, songsRepo: songsRepo);

      await container.read(libraryProvider.future);
      // Resolve songsProvider once so a later rebuild is observable.
      await container.read(songsProvider.future);
      expect(songsRepo.getSongsCallCount, 1);

      await container
          .read(libraryProvider.notifier)
          .createChart(_bandA, title: 'Stardust', songId: 42);

      // Invalidation alone doesn't rebuild until the provider is read again.
      await container.read(songsProvider.future);
      expect(songsRepo.getSongsCallCount, 2);
    });

    test('creating a chart without a linked song does not invalidate songsProvider',
        () async {
      final repo = _FakeRepo(charts: const []);
      final songsRepo = _FakeSongsRepo();
      final container = _container(repo, songsRepo: songsRepo);

      await container.read(libraryProvider.future);
      await container.read(songsProvider.future);
      expect(songsRepo.getSongsCallCount, 1);

      await container
          .read(libraryProvider.notifier)
          .createChart(_bandA, title: 'Stardust');

      await container.read(songsProvider.future);
      expect(songsRepo.getSongsCallCount, 1);
    });
  });

  group('LibraryNotifier.deleteChart', () {
    test('removes by chart id regardless of band', () async {
      const c1 = Chart(
        id: 11,
        bandId: 1,
        title: 'A',
        composer: '',
        description: '',
        price: 0,
        isPublic: false,
        uploadsCount: 0,
        uploads: [],
        band: ChartBand(id: 1, name: 'A', isPersonal: false),
      );
      const c2 = Chart(
        id: 12,
        bandId: 2,
        title: 'B',
        composer: '',
        description: '',
        price: 0,
        isPublic: false,
        uploadsCount: 0,
        uploads: [],
        band: ChartBand(id: 2, name: 'B', isPersonal: false),
      );
      final repo = _FakeRepo(charts: [c1, c2]);
      final container = _container(repo);

      await container.read(libraryProvider.future);

      await container.read(libraryProvider.notifier).deleteChart(1, 11);

      final state = container.read(libraryProvider).value!;
      expect(state.charts.map((c) => c.id), [12]);
      expect(repo.lastDeletedChartId, 11);
    });
  });

  group('updateChartSong', () {
    Chart chart(int id, {ChartSongRef? song}) => Chart(
          id: id,
          bandId: 1,
          title: 'Chart $id',
          composer: '',
          description: '',
          price: 0,
          isPublic: false,
          uploadsCount: 0,
          uploads: const [],
          band: const ChartBand(id: 1, name: 'Band', isPersonal: false),
          song: song,
        );

    test('links a song, patches local state, keeps the stamped band', () async {
      final repo = _FakeRepo(charts: [chart(11)]);
      final songsRepo = _FakeSongsRepo();
      final container = ProviderContainer(overrides: [
        libraryRepositoryProvider.overrideWithValue(repo),
        songsRepositoryProvider.overrideWithValue(songsRepo),
        selectedBandProvider.overrideWith(_StubBand.new),
      ]);
      addTearDown(container.dispose);
      await container.read(libraryProvider.future);

      await container
          .read(libraryProvider.notifier)
          .updateChartSong(1, 11, songId: 7);

      expect(repo.lastPatchedChartId, 11);
      expect(repo.lastPatchedSongId, 7);
      final state = container.read(libraryProvider).value!;
      final updated = state.charts.singleWhere((c) => c.id == 11);
      expect(updated.song?.id, 7);
      expect(updated.band?.name, 'Band',
          reason: 'local band stamp must survive the patch');
    });

    test('unlinks with songId null', () async {
      final repo = _FakeRepo(
          charts: [chart(11, song: const ChartSongRef(id: 7, title: 'S'))]);
      final container = ProviderContainer(overrides: [
        libraryRepositoryProvider.overrideWithValue(repo),
        songsRepositoryProvider.overrideWithValue(_FakeSongsRepo()),
        selectedBandProvider.overrideWith(_StubBand.new),
      ]);
      addTearDown(container.dispose);
      await container.read(libraryProvider.future);

      await container
          .read(libraryProvider.notifier)
          .updateChartSong(1, 11, songId: null);

      expect(repo.lastPatchHadSongId, true);
      expect(repo.lastPatchedSongId, isNull);
      final state = container.read(libraryProvider).value!;
      expect(state.charts.singleWhere((c) => c.id == 11).song, isNull);
    });

    test('invalidates songsProvider so song.charts refreshes', () async {
      final songsRepo = _FakeSongsRepo();
      final container = ProviderContainer(overrides: [
        libraryRepositoryProvider.overrideWithValue(_FakeRepo(charts: [chart(11)])),
        songsRepositoryProvider.overrideWithValue(songsRepo),
        selectedBandProvider.overrideWith(_StubBand.new),
      ]);
      addTearDown(container.dispose);
      await container.read(libraryProvider.future);
      await container.read(songsProvider.future);
      final callsBefore = songsRepo.getSongsCallCount;

      await container
          .read(libraryProvider.notifier)
          .updateChartSong(1, 11, songId: 7);
      await container.read(songsProvider.future);

      expect(songsRepo.getSongsCallCount, greaterThan(callsBefore));
    });
  });
}
