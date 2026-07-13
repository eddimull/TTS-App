import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'models/song.dart';

class SongsRepository {
  SongsRepository(this._dio);

  final Dio _dio;

  /// Fetches the band's songs plus the server-defined genre list.
  ///
  /// The API defaults to active-only (search + setlist picker behaviour);
  /// pass [includeInactive] for the management screen.
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandSongs(bandId),
      queryParameters: {if (includeInactive) 'include_inactive': 1},
    );

    final data = response.data!;
    final rawSongs = data['songs'] as List<dynamic>;
    final rawGenres = data['genres'] as List<dynamic>? ?? const [];
    return (
      songs: rawSongs.cast<Map<String, dynamic>>().map(Song.fromJson).toList(),
      genres: rawGenres.cast<String>(),
    );
  }

  /// Creates a song for [bandId]. [song.id] is ignored (use 0 for drafts).
  Future<Song> createSong(int bandId, Song song) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandSongs(bandId),
      data: song.toUpdateJson(),
    );
    return Song.fromJson(response.data!['song'] as Map<String, dynamic>);
  }

  /// Updates an existing song (full writable-field PATCH).
  Future<Song> updateSong(int bandId, Song song) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileBandSong(bandId, song.id),
      data: song.toUpdateJson(),
    );
    return Song.fromJson(response.data!['song'] as Map<String, dynamic>);
  }

  /// Deletes a song. Server enforces owner-only (403 otherwise).
  Future<void> deleteSong(int bandId, int songId) async {
    await _dio.delete(ApiEndpoints.mobileBandSong(bandId, songId));
  }

  /// BPM lookup passthrough, e.g. `{"bpm": 100, "song_key": "E♭m"}`.
  /// Keys may be absent when the external service finds nothing.
  Future<Map<String, dynamic>> lookupBpm({
    required String title,
    String? artist,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileSongsLookup,
      queryParameters: {
        'title': title,
        if (artist != null && artist.isNotEmpty) 'artist': artist,
      },
    );
    return response.data ?? const {};
  }
}

final songsRepositoryProvider = Provider<SongsRepository>((ref) {
  return SongsRepository(ref.watch(apiClientProvider).dio);
});
