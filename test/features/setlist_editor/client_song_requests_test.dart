import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';

void main() {
  group('ClientSongRequests.fromJson', () {
    test('parses ids and source', () {
      final r = ClientSongRequests.fromJson({
        'must_play': [1, 2],
        'do_not_play': [3],
        'source': {
          'instance_id': 9,
          'name': 'Wedding Questionnaire',
          'recipient_name': 'Jane Doe',
          'submitted_at': '2026-09-12T15:04:05+00:00',
        },
      });

      expect(r.mustPlayIds, {1, 2});
      expect(r.doNotPlayIds, {3});
      expect(r.sourceName, 'Wedding Questionnaire');
      expect(r.recipientName, 'Jane Doe');
      expect(r.submittedAt, DateTime.parse('2026-09-12T15:04:05+00:00'));
    });

    test('tolerates missing source and numeric strings', () {
      final r = ClientSongRequests.fromJson({
        'must_play': ['4'],
        'do_not_play': [],
      });

      expect(r.mustPlayIds, {4});
      expect(r.doNotPlayIds, isEmpty);
      expect(r.sourceName, isNull);
      expect(r.submittedAt, isNull);
    });
  });

  group('ClientSongRequests.statusFor', () {
    const r = ClientSongRequests(mustPlayIds: {1}, doNotPlayIds: {2});

    test('classifies ids', () {
      expect(r.statusFor(1), ClientSongStatus.mustPlay);
      expect(r.statusFor(2), ClientSongStatus.doNotPlay);
      expect(r.statusFor(3), ClientSongStatus.none);
      expect(r.statusFor(null), ClientSongStatus.none);
    });
  });
}
