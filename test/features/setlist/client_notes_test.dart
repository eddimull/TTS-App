import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist/data/models/client_notes.dart';

void main() {
  final notes = ClientNotes.fromJson({
    'requests': [
      {'title': 'Calling Baton Rouge', 'artist': 'Garth Brooks', 'song_id': null, 'kind': 'must_play', 'note': 'Bride is Samantha'},
      {'title': 'I Wanna Dance with Somebody', 'song_id': 117, 'kind': 'must_play'},
      {'title': 'Blame It on the Boogie', 'song_id': 5, 'kind': 'if_time'},
      {'title': 'Pink Pony Club', 'song_id': 9, 'kind': 'do_not_play'},
      {'title': 'Love on Top', 'song_id': null, 'kind': 'intermission'},
      {'title': 'Perfect', 'song_id': null, 'kind': 'special_moment'},
      {'title': 'Junk', 'kind': 'not_a_kind'},
      {'kind': 'must_play'},
    ],
    'song_notes': [
      {'title': 'September', 'song_id': 112, 'note': 'Sing "dancing in October"'},
    ],
    'rules': ['No slow songs', ''],
    'crowd': 'Young crowd',
  });

  test('drops malformed requests and empty rules', () {
    expect(notes.requests, hasLength(6));
    expect(notes.rules, ['No slow songs']);
    expect(notes.crowd, 'Young crowd');
  });

  test('only must-play, if-time and special moments are pickable', () {
    expect(notes.pickable.map((r) => r.title),
        ['Calling Baton Rouge', 'I Wanna Dance with Somebody', 'Blame It on the Boogie', 'Perfect']);
  });

  test('idsOf collects matched catalog ids per kind', () {
    expect(notes.idsOf({ClientRequestKind.mustPlay}), {117});
    expect(notes.idsOf({ClientRequestKind.doNotPlay}), {9});
  });

  test('song notes match by catalog id or by title', () {
    expect(notes.noteFor(songId: 112), 'Sing "dancing in October"');
    expect(notes.noteFor(title: ' september '), 'Sing "dancing in October"');
    expect(notes.noteFor(songId: 1, title: 'Shout'), isNull);
  });
}
