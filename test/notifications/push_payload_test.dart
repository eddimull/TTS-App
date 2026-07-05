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

    test('parses the event title distinct from the venue address', () {
      final p = PushPayload.fromData({
        'type': 'event_departure',
        'eventKey': 'evt_123',
        'title': 'Smith Wedding',
        'venueAddress': '123 Main St',
      });
      expect(p.title, 'Smith Wedding');
      expect(p.venueAddress, '123 Main St');
    });

    test('title is null when absent', () {
      final p = PushPayload.fromData({'type': 'event_departure', 'eventKey': 'x'});
      expect(p.title, isNull);
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

  group('departure notification id alignment', () {
    test('PushPayload.notificationId equals departureNotificationId for a '
        'departure push, so the rendered push and the scheduled local '
        'notification share one slot', () {
      final p = PushPayload.fromData({
        'type': 'event_departure',
        'eventKey': 'evt_42',
      });
      expect(p.notificationId, departureNotificationId('evt_42'));
    });

    test('departureNotificationId is stable and positive (31-bit)', () {
      final id = departureNotificationId('evt_42');
      expect(id, departureNotificationId('evt_42'));
      expect(id, greaterThanOrEqualTo(0));
    });

    test('different events get different departure ids', () {
      expect(
        departureNotificationId('evt_a'),
        isNot(departureNotificationId('evt_b')),
      );
    });
  });

  group('rehearsal and generic type rendering', () {
    test('rehearsal_cancelled parses type, body and rehearsalId', () {
      final p = PushPayload.fromData({
        'type': 'rehearsal_cancelled',
        'title': 'Rehearsal cancelled',
        'body': 'Tuesday Practice · Tue, Jul 7',
        'rehearsalId': '42',
      });
      expect(p.type, PushType.rehearsalCancelled);
      expect(p.body, 'Tuesday Practice · Tue, Jul 7');
      expect(p.rehearsalId, '42');
    });

    test('rehearsal_restored parses', () {
      final p = PushPayload.fromData({'type': 'rehearsal_restored', 'title': 't', 'body': 'b'});
      expect(p.type, PushType.rehearsalRestored);
    });

    test('unknown type keeps title and body for generic rendering', () {
      final p = PushPayload.fromData({'type': 'event_chat_message', 'title': 'New message', 'body': 'hi'});
      expect(p.type, PushType.unknown);
      expect(p.title, 'New message');
      expect(p.body, 'hi');
    });

    test('notification ids differ per type for the same rehearsal', () {
      final a = PushPayload.fromData({'type': 'rehearsal_cancelled', 'rehearsalId': '42'});
      final b = PushPayload.fromData({'type': 'rehearsal_restored', 'rehearsalId': '42'});
      expect(a.notificationId, isNot(b.notificationId));
    });
  });
}
