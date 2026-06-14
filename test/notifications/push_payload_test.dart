import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/push_payload.dart';

void main() {
  group('PushPayload.fromData', () {
    test('parses a full 8h reminder payload', () {
      final p = PushPayload.fromData({
        'type': 'event_reminder_8h',
        'eventKey': 'evt_123',
        'venueAddress': 'The Blue Room',
        'firstItemTitle': 'Load In',
        'firstItemTime': '2026-06-13T14:00:00',
        'showTime': '2026-06-13T19:00:00',
      });
      expect(p.type, PushType.reminder8h);
      expect(p.eventKey, 'evt_123');
      expect(p.venueAddress, 'The Blue Room');
      expect(p.firstItemTitle, 'Load In');
      expect(p.firstItemTime, '2026-06-13T14:00:00');
      expect(p.showTime, '2026-06-13T19:00:00');
    });

    test('parses a departure payload with missing optional fields', () {
      final p = PushPayload.fromData({
        'type': 'event_departure',
        'eventKey': 'evt_9',
        'venueAddress': 'Somewhere',
        'firstItemTitle': 'Load In',
        'firstItemTime': '2026-06-13T14:00:00',
      });
      expect(p.type, PushType.departure);
      expect(p.showTime, isNull);
    });

    test('unknown type maps to PushType.unknown', () {
      final p = PushPayload.fromData({'type': 'something_else', 'eventKey': 'x'});
      expect(p.type, PushType.unknown);
      expect(p.eventKey, 'x');
    });

    test('missing eventKey yields empty string, never throws', () {
      final p = PushPayload.fromData({'type': 'event_reminder_8h'});
      expect(p.eventKey, '');
    });
  });
}
