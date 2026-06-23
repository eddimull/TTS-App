import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';

void main() {
  test('EventDetail parses media list from json', () {
    final json = {
      'id': 1,
      'key': 'evt-1',
      'title': 'Gig',
      'date': '2026-07-01',
      'can_write': true,
      'members': <dynamic>[],
      'timeline': <dynamic>[],
      'lodging': <dynamic>[],
      'contacts': <dynamic>[],
      'attachments': <dynamic>[],
      'media': [
        {
          'id': 9,
          'filename': 'live.jpg',
          'media_type': 'image',
          'mime_type': 'image/jpeg',
          'file_size': 2048,
          'formatted_size': '2.0 KB',
          'thumbnail_url': '/media/9/thumbnail',
          'created_at': '2026-07-01T10:00:00Z',
        }
      ],
    };

    final detail = EventDetail.fromJson(json);

    expect(detail.media, hasLength(1));
    expect(detail.media.first.id, 9);
    expect(detail.media.first.mediaType, 'image');
    expect(detail.media.first.thumbnailUrl, '/media/9/thumbnail');
  });

  test('EventDetail media defaults to empty when absent', () {
    final json = {
      'id': 1, 'key': 'evt-1', 'title': 'Gig', 'date': '2026-07-01',
      'can_write': true, 'members': <dynamic>[], 'timeline': <dynamic>[],
      'lodging': <dynamic>[], 'contacts': <dynamic>[], 'attachments': <dynamic>[],
    };
    expect(EventDetail.fromJson(json).media, isEmpty);
  });
}
