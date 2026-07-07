import 'package:flutter_test/flutter_test.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'package:tts_bandmate/core/network/pusher_connection.dart';

/// Counts init/connect/subscribe/unsubscribe calls without touching any
/// platform channel — overrides every method the real plugin would route
/// through `MethodChannel.invokeMethod`.
class FakePusherChannelsFlutter extends PusherChannelsFlutter {
  int initCalls = 0;
  int connectCalls = 0;
  final List<String> subscribedChannels = [];
  final List<String> unsubscribedChannels = [];

  Function(String channelName, String socketId, dynamic options)?
      capturedAuthorizer;
  Function(String message, dynamic error)? capturedOnSubscriptionError;

  @override
  Future<void> init({
    required String apiKey,
    required String cluster,
    bool? useTLS,
    int? activityTimeout,
    int? pongTimeout,
    int? maxReconnectionAttempts,
    int? maxReconnectGapInSeconds,
    String? proxy,
    bool? enableStats,
    List<String>? disabledTransports,
    List<String>? enabledTransports,
    bool? ignoreNullOrigin,
    String? authEndpoint,
    String? authTransport,
    Map<String, Map<String, String>>? authParams,
    bool? logToConsole,
    Function(String currentState, String previousState)?
        onConnectionStateChange,
    Function(String channelName, dynamic data)? onSubscriptionSucceeded,
    Function(String message, dynamic error)? onSubscriptionError,
    Function(String event, String reason)? onDecryptionFailure,
    Function(String message, int? code, dynamic error)? onError,
    Function(PusherEvent event)? onEvent,
    Function(String channelName, PusherMember member)? onMemberAdded,
    Function(String channelName, PusherMember member)? onMemberRemoved,
    Function(String channelName, String socketId, dynamic options)?
        onAuthorizer,
    Function(String channelName, int subscriptionCount)?
        onSubscriptionCount,
  }) async {
    initCalls++;
    capturedAuthorizer = onAuthorizer;
    capturedOnSubscriptionError = onSubscriptionError;
  }

  @override
  Future<void> connect() async {
    connectCalls++;
  }

  @override
  Future<PusherChannel> subscribe({
    required String channelName,
    var onSubscriptionSucceeded,
    var onSubscriptionError,
    var onMemberAdded,
    var onMemberRemoved,
    var onEvent,
    var onSubscriptionCount,
  }) async {
    subscribedChannels.add(channelName);
    return PusherChannel(channelName: channelName, onEvent: onEvent);
  }

  @override
  Future<void> unsubscribe({required String channelName}) async {
    unsubscribedChannels.add(channelName);
  }
}

void main() {
  group('decodePusherData', () {
    test('decodes a JSON object string', () {
      expect(
        decodePusherData('{"model":"bookings","id":1,"action":"updated"}'),
        {'model': 'bookings', 'id': 1, 'action': 'updated'},
      );
    });

    test('passes through an already-decoded map', () {
      expect(decodePusherData({'a': 1}), {'a': 1});
    });

    test('returns null for null, empty, non-JSON, and non-object payloads', () {
      expect(decodePusherData(null), isNull);
      expect(decodePusherData(''), isNull);
      expect(decodePusherData('not json'), isNull);
      expect(decodePusherData('[1,2]'), isNull);
      expect(decodePusherData(42), isNull);
    });
  });

  group('PusherConnection', () {
    late FakePusherChannelsFlutter fake;
    late PusherConnection connection;

    setUp(() {
      fake = FakePusherChannelsFlutter();
      connection = PusherConnection(
        () async => 'test-token',
        getInstance: () => fake,
        pusherKey: 'test-pusher-key',
      );
    });

    test('two sequential subscribes init/connect exactly once each', () async {
      final unsub1 = await connection.subscribe('private-band.1', (_, __) {});
      final unsub2 = await connection.subscribe('private-band.2', (_, __) {});

      expect(fake.initCalls, 1);
      expect(fake.connectCalls, 1);
      expect(fake.subscribedChannels, ['private-band.1', 'private-band.2']);
      expect(unsub1, isNotNull);
      expect(unsub2, isNotNull);
    });

    test('returned unsubscribe callback unsubscribes the right channel',
        () async {
      final unsub = await connection.subscribe('private-band.5', (_, __) {});
      await unsub!.call();

      expect(fake.unsubscribedChannels, ['private-band.5']);
    });

    test('no token returns null without initializing', () async {
      final noTokenConnection = PusherConnection(
        () async => null,
        getInstance: () => fake,
        pusherKey: 'test-pusher-key',
      );

      final result =
          await noTokenConnection.subscribe('private-band.1', (_, __) {});

      expect(result, isNull);
      expect(fake.initCalls, 0);
      expect(fake.subscribedChannels, isEmpty);
    });

    test('no pusher key configured returns null without initializing',
        () async {
      final noKeyConnection = PusherConnection(
        () async => 'test-token',
        getInstance: () => fake,
        // pusherKey defaults to AppConfig.pusherKey, which is '' in tests
        // (no PUSHER_APP_KEY dart-define) — exercises the same branch.
      );

      final result =
          await noKeyConnection.subscribe('private-band.1', (_, __) {});

      expect(result, isNull);
      expect(fake.initCalls, 0);
      expect(fake.subscribedChannels, isEmpty);
    });
  });
}
