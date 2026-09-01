import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/services/push_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tts.band/launch_notification');

  PushService service() => PushService(FlutterLocalNotificationsPlugin());

  void stubChannel(Object? Function() reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'get');
      return reply();
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('routes a stashed cold-start chat tap to its conversation', () async {
    stubChannel(() => <Object?, Object?>{
          'type': 'chat_message',
          'conversationId': '5',
          'aps': <Object?, Object?>{'alert': 'hi'},
          'gcm.message_id': 'abc123',
        });

    final routes = <String>[];
    await service().consumeLaunchNotification(routes.add);

    expect(routes, ['/conversations/5']);
  });

  test('no stashed launch notification routes nowhere', () async {
    stubChannel(() => null);

    final routes = <String>[];
    await service().consumeLaunchNotification(routes.add);

    expect(routes, isEmpty);
  });

  test('a payload with no destination routes nowhere', () async {
    stubChannel(() => <Object?, Object?>{'type': 'event_reminder_8h'});

    final routes = <String>[];
    await service().consumeLaunchNotification(routes.add);

    expect(routes, isEmpty);
  });

  test('missing native channel (Android / old binary) is a silent no-op',
      () async {
    // No stub registered: the call surfaces MissingPluginException, which the
    // service must swallow — Android never registers this channel.
    final routes = <String>[];
    await service().consumeLaunchNotification(routes.add);

    expect(routes, isEmpty);
  });
}
