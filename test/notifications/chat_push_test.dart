import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/push_payload.dart';
import 'package:tts_bandmate/features/notifications/data/push_route.dart';
import 'package:tts_bandmate/features/notifications/services/push_service.dart';

void main() {
  test('chat_message routes to the conversation thread', () {
    expect(
      routeForPushData({'type': 'chat_message', 'conversationId': '5'}),
      '/conversations/5',
    );
  });

  test('chat_message without conversationId routes nowhere', () {
    expect(routeForPushData({'type': 'chat_message'}), isNull);
  });

  test('payload parses chat type + conversationId with stable dedupe id', () {
    final p = PushPayload.fromData(
        {'type': 'chat_message', 'conversationId': '5', 'body': 'yo'});
    expect(p.type, PushType.chatMessage);
    expect(p.conversationId, '5');
    expect(p.notificationId,
        PushPayload.fromData({'type': 'chat_message', 'conversationId': '5'})
            .notificationId);
  });

  group('shouldSuppressChatPush (currentOpenConversation source of truth)',
      () {
    PushPayload chatPayload(String conversationId) => PushPayload.fromData({
          'type': 'chat_message',
          'conversationId': conversationId,
          'body': 'hey',
        });

    test(
        'suppressed when currentOpenConversation returns the message\'s '
        'conversation id', () {
      expect(
        shouldSuppressChatPush(chatPayload('5'), () => 5),
        isTrue,
      );
    });

    test('rendered when currentOpenConversation is null (no thread open)',
        () {
      expect(
        shouldSuppressChatPush(chatPayload('5'), null),
        isFalse,
      );
    });

    test(
        'rendered when currentOpenConversation returns a different '
        'conversation id', () {
      expect(
        shouldSuppressChatPush(chatPayload('5'), () => 9),
        isFalse,
      );
    });

    test('rendered when currentOpenConversation itself returns null', () {
      expect(
        shouldSuppressChatPush(chatPayload('5'), () => null),
        isFalse,
      );
    });

    test('non-chat payloads are never suppressed by an open conversation',
        () {
      final departure = PushPayload.fromData({'type': 'event_departure'});
      expect(
        shouldSuppressChatPush(departure, () => 5),
        isFalse,
      );
    });
  });

  group('PushService.handleLocalNotificationResponse (tap deep-linking)', () {
    test('a response carrying a route payload invokes onLocalTap with it',
        () {
      final push = PushService(FlutterLocalNotificationsPlugin());
      String? routed;
      push.onLocalTap = (route) => routed = route;

      push.handleLocalNotificationResponse(const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotification,
        payload: '/conversations/5',
      ));

      expect(routed, '/conversations/5');
    });

    test('a response with a null payload does not invoke onLocalTap', () {
      final push = PushService(FlutterLocalNotificationsPlugin());
      var called = false;
      push.onLocalTap = (_) => called = true;

      push.handleLocalNotificationResponse(const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotification,
      ));

      expect(called, isFalse);
    });

    test('a response with an empty payload does not invoke onLocalTap', () {
      final push = PushService(FlutterLocalNotificationsPlugin());
      var called = false;
      push.onLocalTap = (_) => called = true;

      push.handleLocalNotificationResponse(const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotification,
        payload: '',
      ));

      expect(called, isFalse);
    });
  });
}
