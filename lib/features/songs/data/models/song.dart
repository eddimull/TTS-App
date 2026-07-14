/// Lead singer block on a [Song] (`"lead_singer": {id, display_name}|null`).
class SongLeadSinger {
  const SongLeadSinger({required this.id, required this.displayName});

  final int id;
  final String displayName;

  factory SongLeadSinger.fromJson(Map<String, dynamic> json) => SongLeadSinger(
        id: (json['id'] as num).toInt(),
        displayName: json['display_name'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'display_name': displayName};
}

/// Minimal reference to another song — the transition-song block
/// (`"transition_song": {id, title, artist}|null`).
class SongRef {
  const SongRef({required this.id, required this.title, this.artist = ''});

  final int id;
  final String title;
  final String artist;

  factory SongRef.fromJson(Map<String, dynamic> json) => SongRef(
        id: (json['id'] as num).toInt(),
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'artist': artist};
}

/// Linked sheet-music summary carried on a [Song] (`"charts": [{id, title}]`).
class SongChartSummary {
  const SongChartSummary({required this.id, required this.title});

  final int id;
  final String title;

  factory SongChartSummary.fromJson(Map<String, dynamic> json) =>
      SongChartSummary(
        id: (json['id'] as num).toInt(),
        title: json['title'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title};
}

/// A band repertoire song, as returned by
/// GET /api/mobile/bands/{band}/songs.
class Song {
  const Song({
    required this.id,
    required this.bandId,
    required this.title,
    this.artist = '',
    this.songKey = '',
    this.genre = '',
    this.bpm = 0,
    this.notes = '',
    this.rating,
    this.energy,
    this.active = true,
    this.leadSinger,
    this.transitionSong,
    this.charts = const [],
  });

  final int id;
  final int bandId;
  final String title;
  final String artist;
  final String songKey;
  final String genre;

  /// Beats per minute; 0 means unset (the API sends `bpm ?? 0`).
  final int bpm;
  final String notes;

  /// 1–10, null when unrated.
  final int? rating;

  /// 1–10, null when unset.
  final int? energy;
  final bool active;
  final SongLeadSinger? leadSinger;
  final SongRef? transitionSong;
  final List<SongChartSummary> charts;

  factory Song.fromJson(Map<String, dynamic> json) => Song(
        id: (json['id'] as num).toInt(),
        bandId: (json['band_id'] as num).toInt(),
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        songKey: json['song_key'] as String? ?? '',
        genre: json['genre'] as String? ?? '',
        bpm: (json['bpm'] as num?)?.toInt() ?? 0,
        notes: json['notes'] as String? ?? '',
        rating: (json['rating'] as num?)?.toInt(),
        energy: (json['energy'] as num?)?.toInt(),
        active: json['active'] as bool? ?? true,
        leadSinger: json['lead_singer'] is Map<String, dynamic>
            ? SongLeadSinger.fromJson(json['lead_singer'] as Map<String, dynamic>)
            : null,
        transitionSong: json['transition_song'] is Map<String, dynamic>
            ? SongRef.fromJson(json['transition_song'] as Map<String, dynamic>)
            : null,
        charts: (json['charts'] as List<dynamic>?)
                ?.map((c) => SongChartSummary.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  /// Full round-trip serialisation (state persistence, tests).
  Map<String, dynamic> toJson() => {
        'id': id,
        'band_id': bandId,
        'title': title,
        'artist': artist,
        'song_key': songKey,
        'genre': genre,
        'bpm': bpm,
        'notes': notes,
        'rating': rating,
        'energy': energy,
        'active': active,
        'lead_singer': leadSinger?.toJson(),
        'transition_song': transitionSong?.toJson(),
        'charts': charts.map((c) => c.toJson()).toList(),
      };

  /// Writable-field payload for POST / PATCH. The server derives the band
  /// from the route, and its rules reject bpm 0 (min:1) — empty values are
  /// sent as null to satisfy the `nullable|…` validation rules.
  Map<String, dynamic> toUpdateJson() => {
        'title': title,
        'artist': artist.isEmpty ? null : artist,
        'song_key': songKey.isEmpty ? null : songKey,
        'genre': genre.isEmpty ? null : genre,
        'bpm': bpm > 0 ? bpm : null,
        'notes': notes.isEmpty ? null : notes,
        'rating': rating,
        'energy': energy,
        'lead_singer_id': leadSinger?.id,
        'transition_song_id': transitionSong?.id,
        'active': active,
      };
}
