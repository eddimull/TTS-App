import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/push_payload.dart';
import 'package:tts_bandmate/features/notifications/services/push_service.dart';

void main() {
  test('renderBody maps payload fields into the reminder body', () {
    final p = PushPayload.fromData({
      'type': 'event_reminder_8h',
      'eventKey': 'e1',
      'venueAddress': 'The Blue Room',
      'firstItemTitle': 'Load In',
      'firstItemTime': '2026-06-13T14:00:00',
      'showTime': '2026-06-13T19:00:00',
    });
    expect(renderBody(p), 'The Blue Room · Load In 2:00pm, Show 7:00pm');
  });
}
