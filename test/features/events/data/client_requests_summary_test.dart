import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/client_requests_summary.dart';
import 'package:tts_bandmate/features/setlist/data/models/client_notes.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';

const _songs = [
  BandSongSummary(id: 1, title: 'September', artist: 'Earth, Wind & Fire'),
  BandSongSummary(id: 2, title: 'casanova', artist: 'Levert'),
  BandSongSummary(id: 3, title: 'Haterz'),
  BandSongSummary(id: 4, title: 'Wonderwall', artist: 'Oasis'),
];

void main() {
  test('null when the client made no picks', () {
    expect(summarizeClientRequests(null, _songs), isNull);
  });

  test('null when every pick is missing from the catalog', () {
    const r = ClientSongRequests(mustPlayIds: {99}, doNotPlayIds: {98});
    expect(summarizeClientRequests(r, _songs), isNull);
  });

  test('resolves names, sorts by title and labels with the artist', () {
    const r = ClientSongRequests(
      mustPlayIds: {1, 2, 3, 99},
      doNotPlayIds: {4},
      sourceName: 'Wedding Questionnaire',
    );
    final s = summarizeClientRequests(r, _songs)!;
    expect(s.mustPlay,
        ['casanova · Levert', 'Haterz', 'September · Earth, Wind & Fire']);
    expect(s.doNotPlay, ['Wonderwall · Oasis']);
    expect(s.sourceName, 'Wedding Questionnaire');
  });

  test('a song picked as both is only listed as do-not-play', () {
    const r = ClientSongRequests(mustPlayIds: {1, 4}, doNotPlayIds: {4});
    final s = summarizeClientRequests(r, _songs)!;
    expect(s.mustPlay, ['September · Earth, Wind & Fire']);
    expect(s.doNotPlay, ['Wonderwall · Oasis']);
  });

  group('free-text requests', () {
    ClientRequest req(String title, ClientRequestKind kind,
            {String? artist, int? id}) =>
        ClientRequest(title: title, kind: kind, artist: artist, songId: id);

    test('join the picks; songs not in the catalog are marked', () {
      const picks = ClientSongRequests(mustPlayIds: {1}, doNotPlayIds: {});
      final notes = ClientNotes(
        requests: [
          req('Atomic Dog', ClientRequestKind.mustPlay,
              artist: 'George Clinton'),
          req('Wonderwall', ClientRequestKind.mustPlay, id: 4),
          req('Casanova', ClientRequestKind.mustPlay), // catalog, by title
          req('September', ClientRequestKind.mustPlay, id: 1), // also picked
          req('Dance No More', ClientRequestKind.ifTime),
          req('Wagon Wheel', ClientRequestKind.doNotPlay),
          req('Perfect', ClientRequestKind.specialMoment),
          req('Cupid Shuffle', ClientRequestKind.intermission),
        ],
        rules: ['No Taylor Swift'],
      );
      final s = summarizeClientRequests(picks, _songs, notes: notes)!;
      expect(s.mustPlay, [
        'Atomic Dog · George Clinton',
        'casanova · Levert',
        'September · Earth, Wind & Fire',
        'Wonderwall · Oasis',
      ]);
      expect(s.ifTime, ['Dance No More']);
      expect(s.doNotPlay, ['Wagon Wheel']);
      expect(s.guidelines, ['No Taylor Swift']);
      expect(s.notInCatalog,
          {'Atomic Dog · George Clinton', 'Dance No More', 'Wagon Wheel'});
    });

    test('do-not-play wins, and must-play wins over if-time', () {
      final notes = ClientNotes(requests: [
        req('Wagon Wheel', ClientRequestKind.mustPlay),
        req('Wagon wheel', ClientRequestKind.doNotPlay),
        req('Atomic Dog', ClientRequestKind.ifTime),
        req('Atomic Dog', ClientRequestKind.mustPlay),
      ]);
      final s = summarizeClientRequests(null, _songs, notes: notes)!;
      expect(s.mustPlay, ['Atomic Dog']);
      expect(s.ifTime, isEmpty);
      expect(s.doNotPlay, ['Wagon wheel']);
    });

    test('free text alone, without picks, is enough', () {
      final s = summarizeClientRequests(null, _songs,
          notes: const ClientNotes(rules: ['No slow songs']))!;
      expect(s.guidelines, ['No slow songs']);
      expect(summarizeClientRequests(null, _songs, notes: const ClientNotes()),
          isNull);
    });
  });

  test('catalog songs sharing a title stay separate', () {
    const songs = [
      BandSongSummary(id: 1, title: 'Hello', artist: 'Adele'),
      BandSongSummary(id: 2, title: 'Hello', artist: 'Lionel Richie'),
    ];
    const r = ClientSongRequests(mustPlayIds: {1}, doNotPlayIds: {2});
    final s = summarizeClientRequests(r, songs)!;
    expect(s.mustPlay, ['Hello · Adele']);
    expect(s.doNotPlay, ['Hello · Lionel Richie']);
  });
}
