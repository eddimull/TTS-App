import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/event_music.dart';
import 'package:tts_bandmate/features/events/data/rehearsal_prep.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_schedule.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';

SetlistEntry _song(int pos, {int? id, String? title, String? custom}) =>
    SetlistEntry(
        type: 'song',
        position: pos,
        songId: id,
        title: title,
        customTitle: custom);
SetlistEntry _break(int pos) => SetlistEntry(type: 'break', position: pos);

RehearsalSchedule _schedule(List<Map<String, dynamic>> rehearsals,
        {bool active = true}) =>
    RehearsalSchedule.fromJson({
      'id': 1,
      'name': 'Weekly',
      'active': active,
      'upcoming_rehearsals': rehearsals,
    });

void main() {
  group('songsToLearn', () {
    test('typed-in songs only, once each, in setlist order', () {
      final list = songsToLearn(EventSetlist(id: 1, status: 'draft', songs: [
        _song(1, id: 5, title: 'September'),
        _song(2, custom: 'Here for a Good Time'),
        _break(3),
        _song(4, custom: 'Boogie Wonderland'),
        _song(5, custom: 'here for a good time '),
        _song(6, custom: ''),
      ]));
      expect(list.map((e) => e.displayTitle),
          ['Here for a Good Time', 'Boogie Wonderland']);
    });

    test('nothing without a setlist', () {
      expect(songsToLearn(null), isEmpty);
    });
  });

  test('splitSets splits at breaks and skips empty sets', () {
    final sets = splitSets(EventSetlist(id: 1, status: 'ready', songs: [
      _break(0),
      _song(1, title: 'A'),
      _song(2, title: 'B'),
      _break(3),
      _break(4),
      _song(5, title: 'C'),
    ]));
    expect(sets.map((s) => s.number), [1, 2]);
    expect(sets[0].songs.map((e) => e.displayTitle), ['A', 'B']);
    expect(sets[1].songs.map((e) => e.displayTitle), ['C']);
  });

  test('mustPlaysOnSetlist ignores songs also marked do-not-play', () {
    final requests =
        const ClientSongRequests(mustPlayIds: {1, 2, 3}, doNotPlayIds: {3});
    final setlist = EventSetlist(id: 1, status: 'ready', songs: [
      _song(1, id: 1),
      _song(2, id: 3),
    ]);
    expect(mustPlaysOnSetlist(requests, setlist), 1);
    expect(mustPlaysOnSetlist(null, setlist), 0);
  });

  test('findCatalogSong ignores case and punctuation', () {
    const songs = [
      BandSongSummary(id: 1, title: "Isn't She Lovely"),
      BandSongSummary(id: 2, title: 'Forever and Ever, Amen'),
    ];
    expect(findCatalogSong('isnt she lovely', songs)?.id, 1);
    expect(findCatalogSong('Forever and Ever Amen', songs)?.id, 2);
    expect(findCatalogSong('Shout', songs), isNull);
    expect(findCatalogSong('', songs), isNull);
  });

  test('EventMusic.hasContent needs songs or picks', () {
    expect(const EventMusic().hasContent, isFalse);
    expect(
        EventMusic(
            setlist: EventSetlist(id: 1, status: 'draft', songs: [
          _song(1, id: 1),
        ])).hasContent,
        isTrue);
  });

  group('rehearsalsBefore', () {
    final now = DateTime(2026, 10, 30, 9);
    final gig = DateTime(2026, 11, 7);

    test('soonest first, between today and the day before the gig', () {
      final list = rehearsalsBefore([
        _schedule([
          {'id': 1, 'date': '2026-11-03', 'time': '19:00'},
          {'id': 2, 'date': '2026-10-29', 'time': '19:00'}, // past
          {'id': 3, 'date': '2026-11-07', 'time': '10:00'}, // gig day
          {'id': 4, 'date': '2026-10-30', 'time': '19:00'}, // today
          {'id': 5, 'date': '2026-11-05', 'is_cancelled': true},
        ]),
      ], gig, now);
      expect(list.map((r) => r.id), [4, 1]);
    });

    test('virtual rehearsals count when they have a key', () {
      final list = rehearsalsBefore([
        _schedule([
          {'date': '2026-11-02', 'is_virtual': true, 'event_key': 'v-1'},
          {'date': '2026-11-01', 'is_virtual': true},
        ]),
      ], gig, now);
      expect(list.single.eventKey, 'v-1');
    });

    test('inactive schedules are left out', () {
      expect(
          rehearsalsBefore([
            _schedule([
              {'id': 1, 'date': '2026-11-03'}
            ], active: false)
          ], gig, now),
          isEmpty);
    });
  });

  group('appendLearnLine', () {
    final gig = DateTime(2026, 11, 7);

    test('appends a line to existing notes', () {
      final r = appendLearnLine(
        notes: 'Bring the PA',
        eventTitle: 'Terreson Wedding',
        eventDate: gig,
        titles: ['Here for a Good Time', 'Boogie Wonderland'],
      )!;
      expect(
          r.notes,
          'Bring the PA\n'
          'Learn for Terreson Wedding (Nov 7): Here for a Good Time, '
          'Boogie Wonderland');
      expect(r.added, ['Here for a Good Time', 'Boogie Wonderland']);
    });

    test('skips songs already in the notes', () {
      final r = appendLearnLine(
        notes: 'Learn for Terreson Wedding (Nov 7): Here for a Good Time',
        eventTitle: 'Terreson Wedding',
        eventDate: gig,
        titles: ['here for a good time', 'Boogie Wonderland'],
      )!;
      expect(r.added, ['Boogie Wonderland']);
      expect(r.notes.split('\n').last,
          'Learn for Terreson Wedding (Nov 7): Boogie Wonderland');
    });

    test('null when everything is already there', () {
      expect(
        appendLearnLine(
          notes: 'Boogie Wonderland',
          eventTitle: 'T',
          eventDate: gig,
          titles: ['Boogie Wonderland'],
        ),
        isNull,
      );
    });

    test('empty notes get just the line', () {
      expect(
        appendLearnLine(
                notes: null, eventTitle: 'T', eventDate: gig, titles: ['A'])!
            .notes,
        'Learn for T (Nov 7): A',
      );
    });
  });

  test('rehearsalLabel', () {
    final s = _schedule([
      {'id': 1, 'date': '2026-11-03', 'time': '19:00'},
      {'id': 2, 'date': '2026-11-04'},
    ]).upcomingRehearsals;
    expect(rehearsalLabel(s[0]), 'Tue, Nov 3, 7:00 PM');
    expect(rehearsalLabel(s[1]), 'Wed, Nov 4');
  });

  test('danceLabel turns keys into words', () {
    expect(danceLabel('first_dance'), 'First dance');
    expect(danceLabel('father_daughter'), 'Father daughter');
    expect(danceLabel('Mother-son'), 'Mother-son');
  });

  test('isPlaceholderSong spots unpicked songs', () {
    for (final s in [
      'TBD',
      'tba',
      'N/A',
      'na',
      'none',
      '?',
      '--',
      '',
      null,
      'To be determined'
    ]) {
      expect(isPlaceholderSong(s), isTrue, reason: '$s');
    }
    expect(isPlaceholderSong('Forever and Ever, Amen'), isFalse);
    expect(isPlaceholderSong('Nonesuch'), isFalse);
  });
}
