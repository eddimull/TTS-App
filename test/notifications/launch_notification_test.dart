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

  group('warm taps pushed from native', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    /// Simulates the AppDelegate calling `tap` on the channel.
    Future<void> nativeTap(Map<Object?, Object?> payload) =>
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('tap', payload)),
          (_) {},
        );

    test('routes a warm tap to its deeplink', () async {
      final routes = <String>[];
      service().listenNativeTaps(routes.add);

      await nativeTap({
        'type': 'notification',
        'deeplink': '/bookings/253/42',
        'gcm.message_id': 'm1',
        'aps': <Object?, Object?>{'alert': 'Booking updated'},
      });

      expect(routes, ['/bookings/253/42']);
    });

    test('the same tap delivered twice routes once', () async {
      final routes = <String>[];
      service().listenNativeTaps(routes.add);

      final payload = {'type': 'chat_message', 'conversationId': '5', 'gcm.message_id': 'dup'};
      await nativeTap(payload);
      await nativeTap(payload);

      expect(routes, ['/conversations/5']);
    });

    test('a tap with no destination routes nowhere', () async {
      final routes = <String>[];
      service().listenNativeTaps(routes.add);

      await nativeTap({'type': 'event_reminder_8h', 'gcm.message_id': 'm2'});

      expect(routes, isEmpty);
    });

    test('claimTap admits each id once and never blocks a missing id', () {
      final s = service();
      expect(s.claimTap('a'), isTrue);
      expect(s.claimTap('a'), isFalse);
      expect(s.claimTap('b'), isTrue);
      expect(s.claimTap(null), isTrue);
      expect(s.claimTap(null), isTrue);
    });

    test('cold-start stash and a later duplicate share the de-dup set', () async {
      stubChannel(() => <Object?, Object?>{
            'type': 'chat_message',
            'conversationId': '7',
            'gcm.message_id': 'same',
          });
      final routes = <String>[];
      final s = service();
      s.listenNativeTaps(routes.add);
      await s.consumeLaunchNotification(routes.add);
      // stubChannel only answers `get`; re-stub so `tap` reaches the handler.
      messenger.setMockMethodCallHandler(channel, null);
      await nativeTap({'type': 'chat_message', 'conversationId': '7', 'gcm.message_id': 'same'});

      expect(routes, ['/conversations/7']);
    });
  });
}
