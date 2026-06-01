import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';

void main() {
  group('SetlistEntry.fromJson', () {
    test('parses a song row', () {
      final entry = SetlistEntry.fromJson({
        'id': 1,
        'type': 'song',
        'position': 1,
        'song_id': 42,
        'title': 'Brown Eyed Girl',
        'artist': 'Van Morrison',
        'song_key': 'G',
        'lead_singer': 'Eddie',
        'notes': null,
      });

      expect(entry.type, 'song');
      expect(entry.songId, 42);
      expect(entry.title, 'Brown Eyed Girl');
      expect(entry.isBreak, false);
    });

    test('parses a break row', () {
      final entry = SetlistEntry.fromJson({
        'id': 5,
        'type': 'break',
        'position': 4,
      });

      expect(entry.isBreak, true);
      expect(entry.title, isNull);
    });
  });

  group('EventSetlist.fromJson', () {
    test('parses a full setlist payload', () {
      final setlist = EventSetlist.fromJson({
        'id': 7,
        'status': 'draft',
        'generated_at': '2026-05-30T12:00:00Z',
        'event_context': 'wedding, upbeat',
        'image_context': [],
        'songs': [
          {'id': 1, 'type': 'song', 'position': 1, 'song_id': 10, 'title': 'A'},
          {'id': 2, 'type': 'break', 'position': 2},
        ],
      });

      expect(setlist.id, 7);
      expect(setlist.status, 'draft');
      expect(setlist.songs.length, 2);
      expect(setlist.songs[1].isBreak, true);
    });

    test('handles null / empty payload defensively', () {
      final setlist = EventSetlist.fromJson({
        'id': 1,
        'status': 'draft',
        'generated_at': null,
        'songs': null,
      });

      expect(setlist.songs, isEmpty);
      expect(setlist.imageContext, isEmpty);
    });
  });
}
