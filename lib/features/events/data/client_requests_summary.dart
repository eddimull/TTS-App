import '../../setlist/data/models/client_notes.dart';
import '../../setlist_editor/data/models/event_setlist.dart';
import 'event_music.dart' show findCatalogSong;

/// The client's song requests for the event's Music tab: song-picker picks
/// and the songs written into the questionnaire's free-text answers.
class ClientRequestsSummary {
  const ClientRequestsSummary({
    required this.mustPlay,
    required this.doNotPlay,
    this.ifTime = const [],
    this.guidelines = const [],
    this.notInCatalog = const {},
    this.sourceName,
  });

  /// "Title · Artist" labels, sorted by title.
  final List<String> mustPlay;
  final List<String> doNotPlay;
  final List<String> ifTime;

  /// Blanket wishes from the free text ("No slow songs", "No Taylor Swift").
  final List<String> guidelines;

  /// Labels of requested songs the band's catalog doesn't have.
  final Set<String> notInCatalog;

  /// Name of the questionnaire the picks came from.
  final String? sourceName;

  bool get isEmpty =>
      mustPlay.isEmpty &&
      doNotPlay.isEmpty &&
      ifTime.isEmpty &&
      guidelines.isEmpty;
}

/// Resolves the picks against the band's catalog and adds the free-text
/// requests in [notes]. Pick IDs missing from the catalog (e.g. a song
/// deleted since) are dropped; free-text songs are kept and marked
/// [ClientRequestsSummary.notInCatalog]. Each song is listed once: do-not-play
/// wins over must-play (matching [ClientSongRequests.statusFor]), must-play
/// over if-time.
ClientRequestsSummary? summarizeClientRequests(
  ClientSongRequests? requests,
  List<BandSongSummary> bandSongs, {
  ClientNotes? notes,
}) {
  if (requests == null && notes == null) return null;
  final byId = {for (final s in bandSongs) s.id: s};

  // Keyed by a normalized title so a pick and the same song typed into the
  // free text count once.
  final must = <String, _Song>{};
  final ifTime = <String, _Song>{};
  final doNot = <String, _Song>{};

  void add(Map<String, _Song> into, String title, String? artist,
          {bool offCatalog = false}) =>
      into.putIfAbsent(_key(title), () => _Song(title, artist, offCatalog));

  for (final id in requests?.mustPlayIds ?? const <int>{}) {
    final s = byId[id];
    if (s != null) add(must, s.title, s.artist);
  }
  for (final id in requests?.doNotPlayIds ?? const <int>{}) {
    final s = byId[id];
    if (s != null) add(doNot, s.title, s.artist);
  }

  for (final r in notes?.requests ?? const <ClientRequest>[]) {
    final into = switch (r.kind) {
      ClientRequestKind.mustPlay => must,
      ClientRequestKind.ifTime => ifTime,
      ClientRequestKind.doNotPlay => doNot,
      // Dances show under Special dances; intermission music isn't the band's.
      ClientRequestKind.specialMoment || ClientRequestKind.intermission => null,
    };
    if (into == null) continue;
    final song = (r.songId != null ? byId[r.songId] : null) ??
        findCatalogSong(r.title, bandSongs);
    if (song != null) {
      add(into, song.title, song.artist);
    } else {
      add(into, r.title, r.artist, offCatalog: true);
    }
  }

  for (final k in doNot.keys) {
    must.remove(k);
    ifTime.remove(k);
  }
  for (final k in must.keys) {
    ifTime.remove(k);
  }

  List<_Song> sorted(Map<String, _Song> songs) => songs.values.toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  final all = [...must.values, ...ifTime.values, ...doNot.values];
  final summary = ClientRequestsSummary(
    mustPlay: [for (final s in sorted(must)) s.label],
    ifTime: [for (final s in sorted(ifTime)) s.label],
    doNotPlay: [for (final s in sorted(doNot)) s.label],
    guidelines: notes?.rules ?? const [],
    notInCatalog: {
      for (final s in all)
        if (s.offCatalog) s.label
    },
    sourceName: requests?.sourceName,
  );
  return summary.isEmpty ? null : summary;
}

String _key(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r"['’]"), '')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

class _Song {
  const _Song(this.title, this.artist, this.offCatalog);
  final String title;
  final String? artist;
  final bool offCatalog;

  String get label =>
      (artist?.isNotEmpty ?? false) ? '$title · $artist' : title;
}
