import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/events_repository.dart';
import '../data/models/event_detail.dart';
import '../data/models/event_summary.dart';

// ── Band events (list) ────────────────────────────────────────────────────────

/// Arguments for [bandEventsProvider].
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

class BandEventsNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<EventSummary>, BandEventsParams> {
  @override
  Future<List<EventSummary>> build(BandEventsParams arg) async {
    final repo = ref.watch(eventsRepositoryProvider);
    return repo.getBandEvents(arg.bandId, from: arg.from, to: arg.to);
  }

  /// Re-fetches the list from the server.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () {
        final repo = ref.read(eventsRepositoryProvider);
        return repo.getBandEvents(arg.bandId, from: arg.from, to: arg.to);
      },
    );
  }
}

/// Provides the list of [EventSummary] for a given band.
///
/// Usage:
/// ```dart
/// final events = ref.watch(
///   bandEventsProvider(BandEventsParams(bandId: 42)),
/// );
/// ```
final bandEventsProvider = AutoDisposeAsyncNotifierProviderFamily<
    BandEventsNotifier, List<EventSummary>, BandEventsParams>(
  BandEventsNotifier.new,
);

// ── Event detail (single) ─────────────────────────────────────────────────────

/// Provides the [EventDetail] for a single event [key].
///
/// Usage:
/// ```dart
/// final detail = ref.watch(eventDetailProvider('abc123'));
/// ```
final eventDetailProvider =
    AutoDisposeFutureProviderFamily<EventDetail, String>((ref, key) async {
  final repo = ref.watch(eventsRepositoryProvider);
  return repo.getEventDetail(key);
});
