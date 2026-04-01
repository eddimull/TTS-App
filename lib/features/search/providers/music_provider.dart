import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import '../data/models/search_models.dart';
import '../data/music_repository.dart';

// selectedBandProvider is an AsyncNotifierProvider<..., int?> so we unwrap
// with .valueOrNull — returns null while loading or on error, which is fine
// since we treat null bandId as "not ready" and return an empty list.

final songsProvider = AutoDisposeFutureProvider<List<SongResult>>((ref) async {
  final bandId = ref.watch(selectedBandProvider).valueOrNull;
  if (bandId == null) return [];
  return ref.watch(musicRepositoryProvider).songs(bandId);
});

final chartsProvider =
    AutoDisposeFutureProvider<List<ChartResult>>((ref) async {
  final bandId = ref.watch(selectedBandProvider).valueOrNull;
  if (bandId == null) return [];
  return ref.watch(musicRepositoryProvider).charts(bandId);
});
