import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_message.dart';

void main() {
  test('parses message with payload suggestions and plan', () {
    final msg = PlannerMessage.fromJson({
      'id': 5,
      'role': 'assistant',
      'content': 'Here is a plan',
      'status': 'complete',
      'payload': {
        'suggestions': ['Draft a plan', 'New material'],
        'plan': {
          'title': 'Wedding plan',
          'items': [
            {'song_id': 42, 'title': 'At Last', 'reason': 'On the setlist'},
            {'song_id': null, 'title': 'New Tune', 'reason': 'Fits the horns'},
          ],
        },
      },
    });

    expect(msg.isUser, isFalse);
    expect(msg.text, 'Here is a plan');
    expect(msg.suggestions, ['Draft a plan', 'New material']);
    expect(msg.plan!.title, 'Wedding plan');
    expect(msg.plan!.items.first.songId, 42);
    expect(msg.plan!.items.last.songId, isNull);
  });

  test('parses message with no payload', () {
    final msg = PlannerMessage.fromJson({'id': 1, 'role': 'user', 'content': 'hi', 'status': 'complete'});
    expect(msg.isUser, isTrue);
    expect(msg.suggestions, isEmpty);
    expect(msg.plan, isNull);
  });
}
