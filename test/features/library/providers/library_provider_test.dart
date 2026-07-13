import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/library/data/library_repository.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';
import 'package:tts_bandmate/features/library/providers/library_provider.dart';

class _FakeRepo implements LibraryRepository {
  _FakeRepo({this.charts = const []});

  List<Chart> charts;
  Chart? lastCreated;
  int? lastDeletedChartId;

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

  // Unused in these tests; satisfy the interface with throws.
  @override
  Future<List<Chart>> getCharts(int bandId) => throw UnimplementedError();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ProviderContainer _container(_FakeRepo repo) {
  final container = ProviderContainer(overrides: [
    libraryRepositoryProvider.overrideWithValue(repo),
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
}
