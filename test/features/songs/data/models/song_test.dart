import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';

void main() {
  group('Song.fromJson', () {
    test('parses a full payload', () {
      final song = Song.fromJson({
        'id': 5,
        'band_id': 2,
        'title': 'Uptown Funk',
        'artist': 'Bruno Mars',
        'song_key': 'Dm',
        'genre': 'Funk',
        'bpm': 115,
        'notes': 'Horns!',
        'rating': 8,
        'energy': 9,
        'active': true,
        'lead_singer': {'id': 3, 'display_name': 'Alex'},
        'transition_song': {'id': 9, 'title': 'Treasure', 'artist': 'Bruno Mars'},
        'charts': [
          {'id': 11, 'title': 'Uptown Funk - Horns'},
        ],
      });

      expect(song.id, 5);
      expect(song.bandId, 2);
      expect(song.title, 'Uptown Funk');
      expect(song.artist, 'Bruno Mars');
      expect(song.songKey, 'Dm');
      expect(song.genre, 'Funk');
      expect(song.bpm, 115);
      expect(song.notes, 'Horns!');
      expect(song.rating, 8);
      expect(song.energy, 9);
      expect(song.active, true);
      expect(song.leadSinger!.id, 3);
      expect(song.leadSinger!.displayName, 'Alex');
      expect(song.transitionSong!.id, 9);
      expect(song.transitionSong!.title, 'Treasure');
      expect(song.charts, hasLength(1));
      expect(song.charts.first.id, 11);
      expect(song.charts.first.title, 'Uptown Funk - Horns');
    });

    test('null-coalesces missing optional fields', () {
      final song = Song.fromJson({
        'id': 1,
        'band_id': 2,
        'title': 'Bare',
        'lead_singer': null,
        'transition_song': null,
      });

      expect(song.artist, '');
      expect(song.songKey, '');
      expect(song.genre, '');
      expect(song.bpm, 0);
      expect(song.notes, '');
      expect(song.rating, isNull);
      expect(song.energy, isNull);
      expect(song.active, true);
      expect(song.leadSinger, isNull);
      expect(song.transitionSong, isNull);
      expect(song.charts, isEmpty);
    });
  });

  group('Song.toUpdateJson', () {
    test('maps writable fields and nested ids', () {
      const song = Song(
        id: 5,
        bandId: 2,
        title: 'Uptown Funk',
        artist: 'Bruno Mars',
        songKey: 'Dm',
        genre: 'Funk',
        bpm: 115,
        notes: 'Horns!',
        rating: 8,
        energy: 9,
        active: false,
        leadSinger: SongLeadSinger(id: 3, displayName: 'Alex'),
        transitionSong: SongRef(id: 9, title: 'Treasure', artist: 'Bruno Mars'),
      );

      expect(song.toUpdateJson(), {
        'title': 'Uptown Funk',
        'artist': 'Bruno Mars',
        'song_key': 'Dm',
        'genre': 'Funk',
        'bpm': 115,
        'notes': 'Horns!',
        'rating': 8,
        'energy': 9,
        'lead_singer_id': 3,
        'transition_song_id': 9,
        'active': false,
      });
    });

    test('sends null for empty strings and zero bpm (server rules: bpm min 1)', () {
      const song = Song(id: 0, bandId: 2, title: 'Bare');

      final json = song.toUpdateJson();
      expect(json['artist'], isNull);
      expect(json['song_key'], isNull);
      expect(json['genre'], isNull);
      expect(json['bpm'], isNull);
      expect(json['notes'], isNull);
      expect(json['rating'], isNull);
      expect(json['energy'], isNull);
      expect(json['lead_singer_id'], isNull);
      expect(json['transition_song_id'], isNull);
      expect(json['active'], true);
    });
  });

  test('toJson round-trips through fromJson', () {
    const song = Song(
      id: 5,
      bandId: 2,
      title: 'Uptown Funk',
      artist: 'Bruno Mars',
      rating: 8,
      leadSinger: SongLeadSinger(id: 3, displayName: 'Alex'),
      charts: [SongChartSummary(id: 11, title: 'Horns')],
    );

    final restored = Song.fromJson(song.toJson());
    expect(restored.id, 5);
    expect(restored.title, 'Uptown Funk');
    expect(restored.rating, 8);
    expect(restored.leadSinger!.displayName, 'Alex');
    expect(restored.charts.first.title, 'Horns');
  });
}
