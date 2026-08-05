import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/selected_band_provider.dart';
import '../data/lodging_repository.dart';
import '../data/models/lodging.dart';

typedef LodgingListState = ({List<LodgingSummary> lodgings, bool canWrite});

class LodgingsNotifier extends AsyncNotifier<LodgingListState> {
  LodgingsNotifier(this._bandId);

  final int _bandId;

  LodgingRepository get _repo => ref.read(lodgingRepositoryProvider);

  @override
  Future<LodgingListState> build() => _repo.getLodgings(_bandId);

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getLodgings(_bandId));
  }

  /// Optimistically removes a deleted lodging from the list.
  void remove(int lodgingId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data((
      lodgings: current.lodgings.where((l) => l.id != lodgingId).toList(),
      canWrite: current.canWrite,
    ));
  }
}

final lodgingsProvider =
    AsyncNotifierProvider.family<LodgingsNotifier, LodgingListState, int>(
  (arg) => LodgingsNotifier(arg),
);

final lodgingDetailProvider =
    FutureProvider.family<({Lodging lodging, bool canWrite}), int>(
        (ref, lodgingId) async {
  final bandId = ref.watch(selectedBandProvider).value;
  if (bandId == null) {
    throw StateError('No band selected');
  }
  return ref.watch(lodgingRepositoryProvider).getLodging(bandId, lodgingId);
});
