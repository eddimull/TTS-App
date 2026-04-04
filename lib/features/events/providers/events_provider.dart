import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/events_repository.dart';
import '../data/models/event_detail.dart';
import '../data/models/event_summary.dart';

class BandEventsParams {
  const BandEventsParams({required this.bandId, this.from, this.to});

  final int bandId;
  final String? from;
  final String? to;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BandEventsParams &&
          runtimeType == other.runtimeType &&
          bandId == other.bandId &&
          from == other.from &&
          to == other.to;

  @override
  int get hashCode => Object.hash(bandId, from, to);
}

class BandEventsNotifier extends AsyncNotifier<List<EventSummary>> {
  BandEventsNotifier(this._params);
  final BandEventsParams _params;

  @override
  Future<List<EventSummary>> build() async {
    final repo = ref.watch(eventsRepositoryProvider);
    return repo.getBandEvents(_params.bandId, from: _params.from, to: _params.to);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      final repo = ref.read(eventsRepositoryProvider);
      return repo.getBandEvents(_params.bandId, from: _params.from, to: _params.to);
    });
  }
}

final bandEventsProvider = AsyncNotifierProvider.family<
    BandEventsNotifier, List<EventSummary>, BandEventsParams>(
  (arg) => BandEventsNotifier(arg),
);

final eventDetailProvider =
    FutureProvider.family<EventDetail, String>((ref, key) async {
  final repo = ref.watch(eventsRepositoryProvider);
  return repo.getEventDetail(key);
});
