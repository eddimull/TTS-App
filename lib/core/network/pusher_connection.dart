import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

import '../config/app_config.dart';
import '../storage/secure_storage.dart';
import 'pusher_authorizer.dart';

typedef PusherJsonHandler = void Function(
    String eventName, Map<String, dynamic> data);

/// Decodes a raw Pusher event payload into a JSON object, or null when the
/// payload is absent/malformed/not an object. Pure — unit-tested directly.
Map<String, dynamic>? decodePusherData(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is! String || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Single owner of the app-wide `PusherChannelsFlutter.getInstance()`
/// singleton. Every feature subscribes through here so no feature ever
/// resets or disconnects the socket underneath another (the pre-existing
/// live-setlist provider used to call `disconnect()` on dispose, which
/// would have killed all other subscriptions).
class PusherConnection {
  PusherConnection(this._readToken);

  final Future<String?> Function() _readToken;

  /// Subscribes to [channelName], delivering decoded JSON events to
  /// [onEvent]. Returns an unsubscribe callback, or null when Pusher is
  /// unconfigured or there is no auth token (callers treat that as
  /// "realtime unavailable", exactly like today).
  Future<Future<void> Function()?> subscribe(
      String channelName, PusherJsonHandler onEvent) async {
    final token = await _readToken();
    if (token == null || AppConfig.pusherKey.isEmpty) return null;

    final pusher = PusherChannelsFlutter.getInstance();
    // init/connect are idempotent enough for repeated calls — this mirrors
    // the previous per-feature behavior (both call sites did exactly this).
    await pusher.init(
      apiKey: AppConfig.pusherKey,
      cluster: AppConfig.pusherCluster,
      onAuthorizer: pusherAuthorizer(token),
    );
    await pusher.connect();

    await pusher.subscribe(
      channelName: channelName,
      // The parameter must be typed `dynamic` (not `PusherEvent`): the
      // plugin's `PusherChannel.onEvent` is `Function(dynamic)?` and in AOT
      // builds a `(PusherEvent) => …` literal throws a contravariance
      // TypeError. Cast inside instead.
      onEvent: (dynamic event) {
        final e = event as PusherEvent;
        final data = decodePusherData(e.data);
        if (data == null) return;
        onEvent(e.eventName, data);
      },
    );

    return () => pusher.unsubscribe(channelName: channelName);
  }
}

final pusherConnectionProvider = Provider<PusherConnection>((ref) {
  return PusherConnection(() => ref.read(secureStorageProvider).readToken());
});
