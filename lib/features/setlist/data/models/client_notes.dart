/// What the client asked for in the questionnaire's free text, as read by
/// the AI when the live session started.
enum ClientRequestKind { mustPlay, ifTime, doNotPlay, intermission, specialMoment }

class ClientRequest {
  const ClientRequest({
    required this.title,
    required this.kind,
    this.artist,
    this.songId,
    this.note,
  });

  final String title;
  final String? artist;

  /// The band's catalog song, when the request matched one.
  final int? songId;
  final ClientRequestKind kind;

  /// Context for the band — who asked, which moment.
  final String? note;

  /// Requests the captain can queue from the picker (intermission songs are
  /// for the break playlist, do-not-play songs are never queued).
  bool get isPickable =>
      kind == ClientRequestKind.mustPlay ||
      kind == ClientRequestKind.ifTime ||
      kind == ClientRequestKind.specialMoment;

  static ClientRequestKind? _kind(Object? raw) => switch (raw) {
        'must_play' => ClientRequestKind.mustPlay,
        'if_time' => ClientRequestKind.ifTime,
        'do_not_play' => ClientRequestKind.doNotPlay,
        'intermission' => ClientRequestKind.intermission,
        'special_moment' => ClientRequestKind.specialMoment,
        _ => null,
      };

  static ClientRequest? fromJson(Map<String, dynamic> json) {
    final kind = _kind(json['kind']);
    final title = json['title'] as String?;
    if (kind == null || title == null || title.isEmpty) return null;
    return ClientRequest(
      title: title,
      kind: kind,
      artist: json['artist'] as String?,
      songId: (json['song_id'] as num?)?.toInt(),
      note: json['note'] as String?,
    );
  }
}

/// A performance instruction tied to a song, e.g. a lyric change.
class ClientSongNote {
  const ClientSongNote({required this.title, required this.note, this.songId});

  final String title;
  final int? songId;
  final String note;
}

class ClientNotes {
  const ClientNotes({
    this.requests = const [],
    this.songNotes = const [],
    this.rules = const [],
    this.crowd,
  });

  final List<ClientRequest> requests;
  final List<ClientSongNote> songNotes;

  /// Blanket constraints ("No slow songs").
  final List<String> rules;
  final String? crowd;

  bool get isEmpty =>
      requests.isEmpty && songNotes.isEmpty && rules.isEmpty && crowd == null;

  Iterable<ClientRequest> get pickable => requests.where((r) => r.isPickable);

  Set<int> idsOf(Set<ClientRequestKind> kinds) => {
        for (final r in requests)
          if (r.songId != null && kinds.contains(r.kind)) r.songId!,
      };

  /// The note for a song as it plays, matched by catalog id or title.
  String? noteFor({int? songId, String? title}) {
    final t = title?.trim().toLowerCase();
    for (final n in songNotes) {
      if (songId != null && n.songId == songId) return n.note;
      if (t != null && n.title.trim().toLowerCase() == t) return n.note;
    }
    return null;
  }

  factory ClientNotes.fromJson(Map<String, dynamic> json) => ClientNotes(
        requests: (json['requests'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClientRequest.fromJson)
            .whereType<ClientRequest>()
            .toList(),
        songNotes: [
          for (final n in (json['song_notes'] as List<dynamic>? ?? const []))
            if (n is Map<String, dynamic> &&
                n['title'] is String &&
                n['note'] is String)
              ClientSongNote(
                title: n['title'] as String,
                note: n['note'] as String,
                songId: (n['song_id'] as num?)?.toInt(),
              ),
        ],
        rules: [
          for (final r in (json['rules'] as List<dynamic>? ?? const []))
            if (r is String && r.isNotEmpty) r,
        ],
        crowd: json['crowd'] as String?,
      );
}
