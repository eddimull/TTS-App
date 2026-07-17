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

  group('buildBackgroundNotification', () {
    test('chat_message builds a spec with title, body, id, and channel', () {
      final spec = buildBackgroundNotification({
        'type': 'chat_message',
        'conversationId': '5',
        'title': 'Sam',
        'body': 'you around?',
      });
      expect(spec, isNotNull);
      expect(spec!.title, 'Sam');
      expect(spec.body, 'you around?');
      expect(spec.channelId, 'band_updates');
      expect(
        spec.id,
        PushPayload.fromData(
                {'type': 'chat_message', 'conversationId': '5'})
            .notificationId,
      );
    });

    test('chat_message with no title falls back to a generic app name', () {
      final spec = buildBackgroundNotification({
        'type': 'chat_message',
        'conversationId': '5',
        'body': 'hi',
      });
      expect(spec!.title, 'TTS Bandmate');
    });

    test(
        'chat_message spec carries the conversation route so a tap on the '
        'background-rendered notification can deep-link', () {
      final spec = buildBackgroundNotification({
        'type': 'chat_message',
        'conversationId': '5',
        'body': 'hi',
      });
      expect(spec!.route, '/conversations/5');
    });

    test('a chat_message with no parseable conversationId has a null route',
        () {
      final spec = buildBackgroundNotification({
        'type': 'chat_message',
        'body': 'hi',
      });
      expect(spec!.route, isNull);
    });

    test('non-chat types return null (out of scope for background render)', () {
      expect(
        buildBackgroundNotification({
          'type': 'event_reminder_8h',
          'eventKey': 'evt_1',
        }),
        isNull,
      );
      expect(
        buildBackgroundNotification({
          'type': 'rehearsal_cancelled',
          'rehearsalId': '1',
        }),
        isNull,
      );
      expect(buildBackgroundNotification({'type': 'unknown'}), isNull);
    });

    test('questionnaire_submitted parses type and renders in background', () {
      final spec = buildBackgroundNotification({
        'type': 'questionnaire_submitted',
        'title': 'Alice submitted the Wedding Intake',
        'body': 'Booking: Smith Wedding',
        'questionnaireId': '3',
        'instanceId': '9',
      });
      expect(spec, isNotNull);
      expect(spec!.title, 'Alice submitted the Wedding Intake');
      expect(spec.route, '/questionnaires/3/instances/9');
    });

    test('two questionnaire instances get distinct notification ids', () {
      PushPayload payload(String instanceId) => PushPayload.fromData({
            'type': 'questionnaire_submitted',
            'instanceId': instanceId,
          });
      expect(payload('1').notificationId,
          isNot(payload('2').notificationId));
    });
  });
}
