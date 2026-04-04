import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    // Start with an empty state; callers invoke load() after selecting a band.
    return const LibraryState();
  }

  Future<void> load(int bandId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(libraryRepositoryProvider);
      final charts = await repo.getCharts(bandId);
      return LibraryState(charts: charts);
    });
  }

  /// Creates a new chart and inserts it into the state list sorted by title.
  Future<Chart> createChart(
    int bandId,
    String title, {
    String? composer,
    String? description,
    double? price,
    bool isPublic = false,
  }) async {
    final repo = ref.read(libraryRepositoryProvider);
    final newChart = await repo.createChart(
      bandId,
      title: title,
      composer: composer,
      description: description,
      price: price,
      isPublic: isPublic,
    );

    // Merge into existing list and re-sort alphabetically.
    final current = state.value ?? const LibraryState();
    final updated = [...current.charts, newChart]
      ..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    state = AsyncData(current.copyWith(charts: updated));
    return newChart;
  }

  /// Removes a chart from the state list and calls the delete API.
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
///
/// Usage:
/// ```dart
/// final chart = ref.watch(chartDetailProvider((bandId: 42, chartId: 7)));
/// ```
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
  final double progress; // 0.0 – 1.0
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
