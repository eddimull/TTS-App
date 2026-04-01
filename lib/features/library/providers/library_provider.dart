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
