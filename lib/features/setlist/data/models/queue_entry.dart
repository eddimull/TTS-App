class QueueEntry {
  const QueueEntry({
    required this.id,
    required this.type,
    this.songId,
    required this.position,
    required this.status,
    this.title,
    this.artist,
    this.songKey,
    this.genre,
    this.bpm,
    this.leadSinger,
    this.crowdReaction,
    required this.isOffSetlist,
    this.playedAt,
  });

  final int id;
  final String type; // 'song' | 'break'
  final int? songId;
  final int position;
  final String status; // 'pending' | 'played' | 'skipped' | 'removed'
  final String? title;
  final String? artist;
  final String? songKey;
  final String? genre;
  final num? bpm;
  final String? leadSinger;
  final String? crowdReaction; // 'positive' | 'negative' | 'neutral'
  final bool isOffSetlist;
  final String? playedAt;

  /// [crowdReaction] uses a closure so it can be cleared to null.
  QueueEntry copyWith({int? position, String? Function()? crowdReaction}) =>
      QueueEntry(
        id: id,
        type: type,
        songId: songId,
        position: position ?? this.position,
        status: status,
        title: title,
        artist: artist,
        songKey: songKey,
        genre: genre,
        bpm: bpm,
        leadSinger: leadSinger,
        crowdReaction:
            crowdReaction != null ? crowdReaction() : this.crowdReaction,
        isOffSetlist: isOffSetlist,
        playedAt: playedAt,
      );

  bool get isBreak => type == 'break';
  bool get isPending => status == 'pending';
  bool get isPlayed => status == 'played';

  factory QueueEntry.fromJson(Map<String, dynamic> json) => QueueEntry(
        id: json['id'] as int,
        type: json['type'] as String? ?? 'song',
        songId: json['song_id'] as int?,
        position: json['position'] as int,
        status: json['status'] as String? ?? 'pending',
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        songKey: json['song_key'] as String?,
        genre: json['genre'] as String?,
        bpm: json['bpm'] as num?,
        leadSinger: json['lead_singer'] as String?,
        crowdReaction: json['crowd_reaction'] as String?,
        isOffSetlist: json['is_off_setlist'] as bool? ?? false,
        playedAt: json['played_at'] as String?,
      );
}
