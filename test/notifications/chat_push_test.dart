import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/push_payload.dart';
import 'package:tts_bandmate/features/notifications/data/push_route.dart';

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
}
