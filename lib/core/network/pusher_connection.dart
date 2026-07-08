import 'dart:convert';

import 'package:flutter/foundation.dart';
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
///
/// Init/connect happen AT MOST ONCE per `PusherConnection` lifetime, memoized
/// via [_ready]. This matters because the plugin's native `init` is NOT
/// idempotent — on both Android and iOS it disconnects and news up the
/// underlying Pusher client, and the Dart side never replays previously
/// subscribed channels afterwards. Calling `init` again while other features
/// are subscribed (e.g. the always-on band channel and the live-setlist/
/// planner channel both subscribing independently) silently kills every
/// other channel's subscription. Memoizing init/connect behind one shared
/// Future means every caller piggybacks on the same connection instead of
/// re-initializing it.
class PusherConnection {
  PusherConnection(this._readToken,
      {PusherChannelsFlutter Function()? getInstance, String? pusherKey})
      : _getInstance = getInstance ?? PusherChannelsFlutter.getInstance,
        _pusherKey = pusherKey ?? AppConfig.pusherKey;

  final Future<String?> Function() _readToken;
  final PusherChannelsFlutter Function() _getInstance;
  final String _pusherKey;

  Future<void>? _ready;

  /// Subscribes to [channelName], delivering decoded JSON events to
  /// [onEvent]. Returns an unsubscribe callback, or null when Pusher is
  /// unconfigured or there is no auth token (callers treat that as
  /// "realtime unavailable", exactly like today).
  Future<Future<void> Function()?> subscribe(
      String channelName, PusherJsonHandler onEvent) async {
    final token = await _readToken();
    if (token == null || _pusherKey.isEmpty) return null;

    final pusher = _getInstance();

    try {
      _ready ??= _initAndConnect(pusher);
      await _ready;
    } catch (_) {
      // Allow a later subscribe() to retry init/connect instead of being
      // stuck forever on a failed attempt.
      _ready = null;
      rethrow;
    }

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

  /// One-time init/connect. The `onAuthorizer` passed to `init` must NOT
  /// close over the token from the first `subscribe()` call — that token can
  /// go stale (e.g. after a re-login) while the plugin instance is never
  /// re-initialized. Instead it re-reads the token from storage on every
  /// auth request, so a fresh token is used every time Pusher needs to
  /// authorize a channel, without needing another `init`.
  Future<void> _initAndConnect(PusherChannelsFlutter pusher) async {
    await pusher.init(
      apiKey: _pusherKey,
      cluster: AppConfig.pusherCluster,
      onAuthorizer: (channelName, socketId, options) async {
        final token = await _readToken();
        if (token == null) {
          throw StateError('No auth token for Pusher auth');
        }
        return pusherAuthorizer(token)(channelName, socketId, options);
      },
      onSubscriptionError: (message, error) {
        debugPrint('PusherConnection: subscription error — $message: $error');
      },
      onError: (message, code, error) {
        debugPrint('PusherConnection: error ($code) — $message: $error');
      },
    );
    await pusher.connect();
  }
}

final pusherConnectionProvider = Provider<PusherConnection>((ref) {
  return PusherConnection(() => ref.read(secureStorageProvider).readToken());
});
