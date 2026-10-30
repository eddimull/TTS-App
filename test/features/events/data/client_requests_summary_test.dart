import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/client_requests_summary.dart';
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
}
