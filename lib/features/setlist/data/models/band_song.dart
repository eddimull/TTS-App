class BandSong {
  const BandSong({
    required this.id,
    required this.title,
    this.artist,
    this.songKey,
    this.genre,
    this.bpm,
    this.leadSinger,
  });

  final int id;
  final String title;
  final String? artist;
  final String? songKey;
  final String? genre;
  final num? bpm;
  final String? leadSinger;

  factory BandSong.fromJson(Map<String, dynamic> json) => BandSong(
        id: json['id'] as int,
        title: json['title'] as String? ?? 'Unknown',
        artist: json['artist'] as String?,
        songKey: json['song_key'] as String?,
        genre: json['genre'] as String?,
        bpm: json['bpm'] as num?,
        leadSinger: json['lead_singer'] as String?,
      );
}
