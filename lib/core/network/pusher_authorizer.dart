import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'dev_tls.dart';

/// Validates the `/broadcasting/auth` response body and shapes it into the
/// payload Pusher's native plugins expect. Pure — unit-tested directly.
///
/// Every value must be a String: the iOS plugin force-casts the payload with
/// `as! [String: String]`, so a non-String value (or a FlutterError from a
/// thrown Dart exception) aborts the process. Laravel normally returns
/// `channel_data` as a JSON string already; anything else is re-encoded.
Map<String, String> buildPusherAuthPayload(
    Map<String, dynamic>? body, int? statusCode, String channelName) {
  final auth = body?['auth'];
  if (auth is! String || auth.isEmpty) {
    throw StateError(
      'Pusher auth failed for "$channelName": '
      '/broadcasting/auth returned no valid "auth" (status '
      '$statusCode, body: $body)',
    );
  }
  String asString(Object v) => v is String ? v : jsonEncode(v);
  final channelData = body!['channel_data'];
  final sharedSecret = body['shared_secret'];
  return {
    'auth': auth,
    if (channelData != null) 'channel_data': asString(channelData),
    if (sharedSecret != null) 'shared_secret': asString(sharedSecret),
  };
}

/// Builds the `onAuthorizer` callback for `pusher_channels_flutter`.
///
/// The plugin does NOT auto-POST to `authEndpoint` when `onAuthorizer` is
/// supplied — it hands the (channelName, socketId) to this callback and expects
/// back the Pusher auth payload, i.e. a map containing an `auth` signature (and
/// optionally `channel_data` for presence channels). The native side
/// force-unwraps `authData["auth"]`, so returning anything without an `auth`
/// key makes the subscription silently fail — the device connects but never
/// subscribes, and no request ever reaches the server.
///
/// Our backend authenticates broadcasting with a Bearer token (Sanctum), so the
/// callback must itself POST to `/broadcasting/auth` with the token and the
/// `socket_id` + `channel_name` form fields Laravel's BroadcastController
/// expects, then return the JSON body (`{ "auth": "..." }`) that Pusher needs.
Future<Map<String, String>> Function(String, String, dynamic) pusherAuthorizer(
  String token,
) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
      // Bound the auth call so a stalled/unreachable server surfaces as an error
      // instead of hanging the subscription forever (mirrors ApiClient).
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  // Debug-only: trust the local HTTPS dev server's self-signed cert so on-device
  // local testing against https://localhost:8710 doesn't fail with a cert error.
  // No-op on web and in release builds. See dev_tls.dart / ApiClient.
  configureDevTls(dio);

  return (String channelName, String socketId, dynamic options) async {
    final res = await dio.post<Map<String, dynamic>>(
      '/broadcasting/auth',
      data: {
        'socket_id': socketId,
        'channel_name': channelName,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    // Laravel returns { "auth": "key:signature" } for private channels and adds
    // "channel_data" for presence channels.
    return buildPusherAuthPayload(res.data, res.statusCode, channelName);
  };
}
