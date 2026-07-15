import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

void main() {
  Map<String, dynamic> baseJson() => {
        'key': 'evt-1',
        'title': 'Summer Gala',
        'date': '2026-07-20',
      };

  test('parses unread_comment_count', () {
    final e = EventSummary.fromJson({...baseJson(), 'unread_comment_count': 3});
    expect(e.unreadCommentCount, 3);
  });

  test('defaults unread_comment_count to 0 on legacy payloads', () {
    final e = EventSummary.fromJson(baseJson());
    expect(e.unreadCommentCount, 0);
  });

  test('parses is_cancelled', () {
    final e = EventSummary.fromJson({...baseJson(), 'is_cancelled': true});
    expect(e.isCancelled, isTrue);
  });

  test('defaults is_cancelled to false on legacy payloads', () {
    final e = EventSummary.fromJson(baseJson());
    expect(e.isCancelled, isFalse);
  });
}
