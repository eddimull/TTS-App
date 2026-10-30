import '../../setlist_editor/data/models/event_setlist.dart';

/// The client's must-play / do-not-play picks resolved to song names, for the
/// event's Music tab.
class ClientRequestsSummary {
  const ClientRequestsSummary({
    required this.mustPlay,
    required this.doNotPlay,
    this.sourceName,
  });

  /// "Title · Artist" labels, sorted by title.
  final List<String> mustPlay;
  final List<String> doNotPlay;

  /// Name of the questionnaire the picks came from.
  final String? sourceName;

  bool get isEmpty => mustPlay.isEmpty && doNotPlay.isEmpty;
}

/// Resolves the pick IDs against the band's catalog. IDs missing from the
/// catalog (e.g. a song deleted since) are dropped. A song picked as both is
/// listed only under do-not-play, matching [ClientSongRequests.statusFor].
ClientRequestsSummary? summarizeClientRequests(
  ClientSongRequests? requests,
  List<BandSongSummary> bandSongs,
) {
  if (requests == null) return null;
  final byId = {for (final s in bandSongs) s.id: s};

  List<String> labels(Iterable<int> ids) {
    final songs = ids.map((id) => byId[id]).whereType<BandSongSummary>().toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return [
      for (final s in songs)
        (s.artist?.isNotEmpty ?? false) ? '${s.title} · ${s.artist}' : s.title,
    ];
  }

  final summary = ClientRequestsSummary(
    mustPlay: labels(requests.mustPlayIds
        .where((id) => !requests.doNotPlayIds.contains(id))),
    doNotPlay: labels(requests.doNotPlayIds),
    sourceName: requests.sourceName,
  );
  return summary.isEmpty ? null : summary;
}
