import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/cache/swr.dart';
import '../data/events_repository.dart';
import '../data/models/event_detail.dart';
import '../data/models/event_summary.dart';
import '../data/models/sub_entry.dart';

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

class BandEventsNotifier extends AsyncNotifier<List<EventSummary>>
    with SwrSupport<List<EventSummary>> {
  BandEventsNotifier(this._params);
  final BandEventsParams _params;

  String get _cacheName =>
      'events:${_params.bandId}:${_params.from ?? ''}:${_params.to ?? ''}';

  Future<({List<EventSummary> value, Map<String, dynamic> raw})>
      _fetch() async {
    final repo = ref.read(eventsRepositoryProvider);
    final result = await repo.getBandEventsRaw(_params.bandId,
        from: _params.from, to: _params.to);
    return (value: result.parsed, raw: result.raw);
  }

  @override
  Future<List<EventSummary>> build() {
    // Watch (not read) so a band/client change rebuilds this provider.
    ref.watch(eventsRepositoryProvider);
    return swrBuild(
      name: _cacheName,
      decode: EventsRepository.parseBandEvents,
      fetch: _fetch,
    );
  }

  Future<void> refresh() => swrRevalidate(name: _cacheName, fetch: _fetch);
}

final bandEventsProvider = AsyncNotifierProvider.family<
    BandEventsNotifier, List<EventSummary>, BandEventsParams>(
  (arg) => BandEventsNotifier(arg),
);

class EventDetailNotifier extends AsyncNotifier<EventDetail>
    with SwrSupport<EventDetail> {
  EventDetailNotifier(this._eventKey);
  final String _eventKey;

  Future<({EventDetail value, Map<String, dynamic> raw})> _fetch() async {
    final result =
        await ref.read(eventsRepositoryProvider).getEventDetailRaw(_eventKey);
    return (value: result.parsed, raw: result.raw);
  }

  @override
  Future<EventDetail> build() {
    ref.watch(eventsRepositoryProvider);
    return swrBuild(
      name: 'event:$_eventKey',
      decode: EventsRepository.parseEventDetail,
      fetch: _fetch,
    );
  }
}

final eventDetailProvider =
    AsyncNotifierProvider.family<EventDetailNotifier, EventDetail, String>(
  (key) => EventDetailNotifier(key),
);

/// Fetches the substitute call list for a specific role on an event.
/// Keyed by a record of (eventKey, bandRoleId) so the cache is per-role.
final eventSubsProvider = FutureProvider.autoDispose
    .family<List<SubEntry>, ({String eventKey, int bandRoleId})>(
        (ref, args) async {
  final repo = ref.watch(eventsRepositoryProvider);
  return repo.fetchSubs(args.eventKey, args.bandRoleId);
});
