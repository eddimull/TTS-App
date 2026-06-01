class SetlistEntry {
  const SetlistEntry({
    this.id,
    required this.type,
    required this.position,
    this.songId,
    this.title,
    this.artist,
    this.customTitle,
    this.customArtist,
    this.songKey,
    this.genre,
    this.bpm,
    this.energy,
    this.leadSinger,
    this.notes,
  });

  final int? id;
  final String type; // 'song' | 'break'
  final int position;
  final int? songId;
  final String? title;
  final String? artist;
  final String? customTitle;
  final String? customArtist;
  final String? songKey;
  final String? genre;
  final int? bpm;
  final int? energy;
  final String? leadSinger;
  final String? notes;

  bool get isBreak => type == 'break';
  bool get isCustom => songId == null && (customTitle ?? '').isNotEmpty;

  String get displayTitle => title ?? customTitle ?? '';
  String? get displayArtist => artist ?? customArtist;

  factory SetlistEntry.fromJson(Map<String, dynamic> json) => SetlistEntry(
        id: json['id'] as int?,
        type: json['type'] as String? ?? 'song',
        position: json['position'] as int? ?? 0,
        songId: json['song_id'] as int?,
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        customTitle: json['custom_title'] as String?,
        customArtist: json['custom_artist'] as String?,
        songKey: json['song_key'] as String?,
        genre: json['genre'] as String?,
        bpm: (json['bpm'] as num?)?.toInt(),
        energy: (json['energy'] as num?)?.toInt(),
        leadSinger: json['lead_singer'] as String?,
        notes: json['notes'] as String?,
      );

  /// Used when sending edits back to the server.
  Map<String, dynamic> toUpdateJson() => {
        'type': type,
        'song_id': songId,
        'custom_title': customTitle,
        'custom_artist': customArtist,
        'notes': notes,
      };

  SetlistEntry copyWith({
    String? type,
    int? position,
    int? songId,
    String? title,
    String? artist,
    String? customTitle,
    String? customArtist,
    String? notes,
  }) =>
      SetlistEntry(
        id: id,
        type: type ?? this.type,
        position: position ?? this.position,
        songId: songId ?? this.songId,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        customTitle: customTitle ?? this.customTitle,
        customArtist: customArtist ?? this.customArtist,
        songKey: songKey,
        genre: genre,
        bpm: bpm,
        energy: energy,
        leadSinger: leadSinger,
        notes: notes ?? this.notes,
      );
}

class EventSetlist {
  const EventSetlist({
    required this.id,
    required this.status,
    this.generatedAt,
    this.eventContext,
    this.imageContext = const [],
    required this.songs,
  });

  final int id;
  final String status; // 'draft' | 'ready'
  final String? generatedAt;
  final String? eventContext;
  final List<Map<String, dynamic>> imageContext;
  final List<SetlistEntry> songs;

  bool get isReady => status == 'ready';

  int get songCount => songs.where((e) => !e.isBreak).length;

  factory EventSetlist.fromJson(Map<String, dynamic> json) => EventSetlist(
        id: json['id'] as int,
        status: json['status'] as String? ?? 'draft',
        generatedAt: json['generated_at'] as String?,
        eventContext: json['event_context'] as String?,
        imageContext: ((json['image_context'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        songs: ((json['songs'] as List<dynamic>?) ?? [])
            .map((e) => SetlistEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  EventSetlist copyWith({
    String? status,
    List<SetlistEntry>? songs,
  }) =>
      EventSetlist(
        id: id,
        status: status ?? this.status,
        generatedAt: generatedAt,
        eventContext: eventContext,
        imageContext: imageContext,
        songs: songs ?? this.songs,
      );
}

class BandSongSummary {
  const BandSongSummary({
    required this.id,
    required this.title,
    this.artist,
    this.songKey,
    this.genre,
    this.bpm,
    this.energy,
    this.leadSinger,
  });

  final int id;
  final String title;
  final String? artist;
  final String? songKey;
  final String? genre;
  final int? bpm;
  final int? energy;
  final String? leadSinger;

  factory BandSongSummary.fromJson(Map<String, dynamic> json) => BandSongSummary(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String?,
        songKey: json['song_key'] as String?,
        genre: json['genre'] as String?,
        bpm: (json['bpm'] as num?)?.toInt(),
        energy: (json['energy'] as num?)?.toInt(),
        leadSinger: json['lead_singer'] as String?,
      );
}
