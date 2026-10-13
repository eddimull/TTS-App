/// The AI's pick for what to play next in a live session.
class LiveSuggestion {
  const LiveSuggestion({
    this.songId,
    required this.title,
    this.artist,
    this.leadSinger,
    this.songKey,
    this.mustPlay = false,
    this.forcedTransition = false,
    this.note,
  });

  /// Null for a client request that isn't in the catalog — see [isCustom].
  final int? songId;

  /// The client's note on the request ("Bride's name is Samantha").
  final String? note;

  /// A client request the band plays but doesn't have in its catalog; it's
  /// queued by title.
  bool get isCustom => songId == null;
  final String title;
  final String? artist;
  final String? leadSinger;
  final String? songKey;

  /// The client asked for this song in a questionnaire.
  final bool mustPlay;

  /// The current song is set to lead straight into this one.
  final bool forcedTransition;

  /// Parses the `/suggest` response; null when there's nothing left to
  /// suggest.
  static LiveSuggestion? fromResponse(Map<String, dynamic> json) {
    final s = json['suggestion'] as Map<String, dynamic>?;
    if (s == null) return null;
    return LiveSuggestion(
      songId: (s['song_id'] as num?)?.toInt(),
      title: s['title'] as String? ?? 'Unknown',
      artist: s['artist'] as String?,
      leadSinger: s['lead_singer'] as String?,
      songKey: s['song_key'] as String?,
      mustPlay: s['must_play'] as bool? ?? false,
      forcedTransition: json['forced_transition'] as bool? ?? false,
      note: s['note'] as String?,
    );
  }
}
