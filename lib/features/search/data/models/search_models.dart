class BookingResult {
  const BookingResult({
    required this.id,
    required this.bandId,
    required this.name,
    required this.venueName,
    required this.date,
    required this.status,
  });

  final int id;
  final int bandId;
  final String name;
  final String venueName;
  final String date;
  final String status;

  factory BookingResult.fromJson(Map<String, dynamic> json) => BookingResult(
        id: json['id'] as int? ?? 0,
        bandId: json['band_id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        venueName: json['venue_name'] as String? ?? '',
        date: json['date'] as String? ?? '',
        status: json['status'] as String? ?? '',
      );
}

class ContactResult {
  const ContactResult({
    required this.id,
    required this.bandId,
    required this.name,
    required this.email,
    required this.phone,
  });

  final int id;
  final int bandId;
  final String name;
  final String email;
  final String phone;

  factory ContactResult.fromJson(Map<String, dynamic> json) => ContactResult(
        id: json['id'] as int? ?? 0,
        bandId: json['band_id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
      );
}

class SongResult {
  const SongResult({
    required this.id,
    required this.bandId,
    required this.title,
    required this.artist,
    required this.songKey,
    required this.genre,
    required this.bpm,
  });

  final int id;
  final int bandId;
  final String title;
  final String artist;
  final String songKey;
  final String genre;
  final int bpm;

  factory SongResult.fromJson(Map<String, dynamic> json) => SongResult(
        id: json['id'] as int? ?? 0,
        bandId: json['band_id'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        songKey: json['song_key'] as String? ?? '',
        genre: json['genre'] as String? ?? '',
        bpm: json['bpm'] as int? ?? 0,
      );
}

class ChartResult {
  const ChartResult({
    required this.id,
    required this.bandId,
    required this.title,
    required this.composer,
  });

  final int id;
  final int bandId;
  final String title;
  final String composer;

  factory ChartResult.fromJson(Map<String, dynamic> json) => ChartResult(
        id: json['id'] as int? ?? 0,
        bandId: json['band_id'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        composer: json['composer'] as String? ?? '',
      );
}

class SearchResults {
  const SearchResults({
    required this.bookings,
    required this.contacts,
    required this.songs,
    required this.charts,
  });

  final List<BookingResult> bookings;
  final List<ContactResult> contacts;
  final List<SongResult> songs;
  final List<ChartResult> charts;

  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
        bookings: (json['bookings'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .map(BookingResult.fromJson)
            .toList(),
        contacts: (json['contacts'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .map(ContactResult.fromJson)
            .toList(),
        songs: (json['songs'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .map(SongResult.fromJson)
            .toList(),
        charts: (json['charts'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .map(ChartResult.fromJson)
            .toList(),
      );

  bool get isEmpty =>
      bookings.isEmpty && contacts.isEmpty && songs.isEmpty && charts.isEmpty;
}
