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

    test('parses integer ids delivered as JSON doubles (web target)', () {
      final setlist = EventSetlist.fromJson({
        'id': 7.0,
        'status': 'draft',
        'songs': [
          {'id': 1.0, 'type': 'song', 'position': 1.0, 'song_id': 10.0},
        ],
      });

      expect(setlist.id, 7);
      expect(setlist.songs.first.id, 1);
      expect(setlist.songs.first.songId, 10);
      expect(setlist.songs.first.position, 1);
    });

    test('songCount excludes break rows', () {
      final setlist = EventSetlist.fromJson({
        'id': 1,
        'status': 'draft',
        'songs': [
          {'id': 1, 'type': 'song', 'position': 1, 'song_id': 10},
          {'id': 2, 'type': 'break', 'position': 2},
          {'id': 3, 'type': 'song', 'position': 3, 'song_id': 11},
        ],
      });

      expect(setlist.songCount, 2);
    });
  });

  group('SetlistEntry edit helpers', () {
    const librarySong = SetlistEntry(
      type: 'song',
      position: 1,
      songId: 42,
      title: 'Brown Eyed Girl',
      notes: 'Opener',
    );

    test('isCustom is false for a break even with a custom title', () {
      const breakEntry =
          SetlistEntry(type: 'break', position: 1, customTitle: 'oops');
      expect(breakEntry.isCustom, false);
    });

    test('isCustom is true for a custom song row', () {
      const custom = SetlistEntry(
        type: 'song',
        position: 1,
        customTitle: 'Garage Anthem',
      );
      expect(custom.isCustom, true);
    });

    test('copyWith can convert a library song to a custom entry', () {
      final custom = librarySong.copyWith(
        songId: null,
        title: null,
        customTitle: 'New Custom Title',
      );

      expect(custom.songId, isNull);
      expect(custom.customTitle, 'New Custom Title');
      expect(custom.isCustom, true);
      // toUpdateJson must reflect the cleared song_id, not the stale 42.
      expect(custom.toUpdateJson()['song_id'], isNull);
      expect(custom.toUpdateJson()['custom_title'], 'New Custom Title');
    });

    test('copyWith can clear notes explicitly', () {
      final cleared = librarySong.copyWith(notes: null);
      expect(cleared.notes, isNull);
    });

    test('copyWith preserves fields when arguments are omitted', () {
      final same = librarySong.copyWith(position: 5);
      expect(same.position, 5);
      expect(same.songId, 42);
      expect(same.title, 'Brown Eyed Girl');
      expect(same.notes, 'Opener');
    });

    test('toUpdateJson emits exactly the server-accepted keys', () {
      expect(librarySong.toUpdateJson().keys.toSet(), {
        'type',
        'song_id',
        'custom_title',
        'custom_artist',
        'notes',
      });
    });
  });
}
