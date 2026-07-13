import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/models/band_summary.dart';
import '../data/library_repository.dart';
import '../data/models/chart.dart';

// ── Library state ─────────────────────────────────────────────────────────────

class LibraryState {
  const LibraryState({
    this.charts = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Chart> charts;
  final bool isLoading;
  final String? error;

  LibraryState copyWith({
    List<Chart>? charts,
    bool? isLoading,
    String? error,
  }) =>
      LibraryState(
        charts: charts ?? this.charts,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

// ── Library notifier ──────────────────────────────────────────────────────────

class LibraryNotifier extends AsyncNotifier<LibraryState> {
  @override
  Future<LibraryState> build() async {
    final repo = ref.read(libraryRepositoryProvider);
    final charts = await repo.getAllCharts();
    return LibraryState(charts: charts);
  }

  /// Re-fetches the merged charts list. Used by pull-to-refresh.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(libraryRepositoryProvider);
      final charts = await repo.getAllCharts();
      return LibraryState(charts: charts);
    });
  }

  /// Creates a new chart for [band], optimistically inserting it (sorted) into
  /// the merged list. The new chart is stamped with a [ChartBand] derived from
  /// [band] so the row avatar and band filter both work without a full reload.
  Future<Chart> createChart(
    BandSummary band,
    {
    required String title,
    String? composer,
    String? description,
    double? price,
    bool isPublic = false,
    int? songId,
  }) async {
    final repo = ref.read(libraryRepositoryProvider);
    final created = await repo.createChart(
      band.id,
      title: title,
      composer: composer,
      description: description,
      price: price,
      isPublic: isPublic,
      songId: songId,
    );

    final stamped = Chart(
      id: created.id,
      bandId: created.bandId,
      title: created.title,
      composer: created.composer,
      description: created.description,
      price: created.price,
      isPublic: created.isPublic,
      uploadsCount: created.uploadsCount,
      uploads: created.uploads,
      band: ChartBand(
        id: band.id,
        name: band.name,
        isPersonal: band.isPersonal,
        logoUrl: band.logoUrl,
      ),
      song: created.song,
    );

    final current = state.value ?? const LibraryState();
    final updated = [...current.charts, stamped]
      ..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    state = AsyncData(current.copyWith(charts: updated));
    return stamped;
  }

  /// Removes a chart from local state and the server.
  Future<void> deleteChart(int bandId, int chartId) async {
    final repo = ref.read(libraryRepositoryProvider);
    await repo.deleteChart(bandId, chartId);

    final current = state.value ?? const LibraryState();
    final updated =
        current.charts.where((c) => c.id != chartId).toList();
    state = AsyncData(current.copyWith(charts: updated));
  }
}

final libraryProvider =
    AsyncNotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);

// ── Chart detail ──────────────────────────────────────────────────────────────

/// Fetches a single [Chart] by band + chart ID.
final chartDetailProvider = FutureProvider.autoDispose
    .family<Chart, ({int bandId, int chartId})>((ref, args) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getChart(args.bandId, args.chartId);
});

// ── Chart upload state ────────────────────────────────────────────────────────

class ChartUploadState {
  const ChartUploadState({
    this.isUploading = false,
    this.progress = 0.0,
    this.error,
    this.lastUploaded,
  });

  final bool isUploading;
  final double progress;
  final String? error;
  final ChartUpload? lastUploaded;

  ChartUploadState copyWith({
    bool? isUploading,
    double? progress,
    String? Function()? error,
    ChartUpload? Function()? lastUploaded,
  }) =>
      ChartUploadState(
        isUploading: isUploading ?? this.isUploading,
        progress: progress ?? this.progress,
        error: error != null ? error() : this.error,
        lastUploaded:
            lastUploaded != null ? lastUploaded() : this.lastUploaded,
      );
}

class ChartUploadNotifier extends Notifier<ChartUploadState> {
  @override
  ChartUploadState build() => const ChartUploadState();

  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  Future<void> uploadChartFile(
    int bandId,
    int chartId, {
    required PlatformFile file,
    required String displayName,
    required int uploadTypeId,
    String? notes,
  }) async {
    state = const ChartUploadState(isUploading: true, progress: 0.0);
    try {
      final upload = await _repo.uploadChartFile(
        bandId,
        chartId,
        file: file,
        displayName: displayName,
        uploadTypeId: uploadTypeId,
        notes: notes,
        onProgress: (p) => state = state.copyWith(progress: p),
      );
      state = ChartUploadState(lastUploaded: upload);
    } catch (e) {
      state = ChartUploadState(error: e.toString());
    }
  }

  Future<void> deleteChartUpload(
    int bandId,
    int chartId,
    int uploadId,
  ) async {
    state = const ChartUploadState(isUploading: true);
    try {
      await _repo.deleteChartUpload(bandId, chartId, uploadId);
      state = const ChartUploadState();
    } catch (e) {
      state = ChartUploadState(error: e.toString());
    }
  }

  void reset() => state = const ChartUploadState();
}

final chartUploadProvider =
    NotifierProvider<ChartUploadNotifier, ChartUploadState>(
  ChartUploadNotifier.new,
);
