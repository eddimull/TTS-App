import '../../setlist_editor/data/models/event_setlist.dart';
import 'client_requests_summary.dart';

/// Everything the Music tab and Music page read from the event's setlist
/// endpoint: the setlist, the band's catalog and the client's picks.
class EventMusic {
  const EventMusic({
    this.setlist,
    this.bandSongs = const [],
    this.requests,
    this.canWrite = false,
  });

  final EventSetlist? setlist;
  final List<BandSongSummary> bandSongs;
  final ClientSongRequests? requests;
  final bool canWrite;

  /// The client's picks resolved to song names; null when there are none.
  ClientRequestsSummary? get requestsSummary =>
      summarizeClientRequests(requests, bandSongs);

  int get songCount => setlist?.songCount ?? 0;

  /// Worth a Music tab: setlist songs or client picks.
  bool get hasContent => songCount > 0 || requestsSummary != null;

  List<SetlistEntry> get toLearn => songsToLearn(setlist);
}

/// Songs on this gig that aren't in the catalog: typed-in setlist entries,
/// once each (by title, ignoring case), in setlist order.
List<SetlistEntry> songsToLearn(EventSetlist? setlist) {
  if (setlist == null) return const [];
  final seen = <String>{};
  return [
    for (final e in setlist.songs)
      if (e.isCustom && seen.add(e.displayTitle.trim().toLowerCase())) e,
  ];
}

/// One set of the setlist: the songs between breaks.
class SetlistSet {
  const SetlistSet(this.number, this.songs);
  final int number;
  final List<SetlistEntry> songs;
}

/// Splits the setlist into sets at its breaks, skipping empty sets.
List<SetlistSet> splitSets(EventSetlist setlist) {
  final sets = <SetlistSet>[];
  var current = <SetlistEntry>[];
  void close() {
    if (current.isNotEmpty) sets.add(SetlistSet(sets.length + 1, current));
    current = [];
  }

  final ordered = [...setlist.songs]
    ..sort((a, b) => a.position.compareTo(b.position));
  for (final e in ordered) {
    if (e.isBreak) {
      close();
    } else {
      current.add(e);
    }
  }
  close();
  return sets;
}

/// How many must-play picks are already on the setlist.
int mustPlaysOnSetlist(ClientSongRequests? requests, EventSetlist? setlist) {
  if (requests == null || setlist == null) return 0;
  final onSetlist = {
    for (final e in setlist.songs)
      if (e.songId != null) e.songId!
  };
  return requests.mustPlayIds
      .where(
          (id) => !requests.doNotPlayIds.contains(id) && onSetlist.contains(id))
      .length;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r"['’]"), '')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

/// Whether two song titles match, ignoring case and punctuation.
bool sameSongTitle(String a, String b) {
  final na = _norm(a);
  return na.isNotEmpty && na == _norm(b);
}

/// The catalog song with this title (ignoring case and punctuation), if any.
BandSongSummary? findCatalogSong(String title, List<BandSongSummary> songs) {
  for (final s in songs) {
    if (sameSongTitle(s.title, title)) return s;
  }
  return null;
}

/// "first_dance" → "First dance".
String danceLabel(String raw) {
  final t = raw.replaceAll('_', ' ').trim();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

final _placeholder = RegExp(
    r'^(tbd|tba|n/?a|none|unknown|to be (determined|decided|announced)|-+|\?+)\.?$',
    caseSensitive: false);

/// A dance song that hasn't been picked yet ("TBD", "N/A", blank).
bool isPlaceholderSong(String? song) {
  final t = (song ?? '').trim();
  return t.isEmpty || _placeholder.hasMatch(t);
}
