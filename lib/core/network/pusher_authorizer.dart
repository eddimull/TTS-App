import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'dev_tls.dart';

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
Future<Map<String, dynamic>> Function(String, String, dynamic) pusherAuthorizer(
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
    // "channel_data" for presence channels. The native plugin force-unwraps
    // authData["auth"], so a missing/non-String value would crash it or silently
    // re-fail the subscription — validate and throw a clear error instead.
    final body = res.data;
    final auth = body?['auth'];
    if (auth is! String || auth.isEmpty) {
      throw StateError(
        'Pusher auth failed for "$channelName": '
        '/broadcasting/auth returned no valid "auth" (status '
        '${res.statusCode}, body: $body)',
      );
    }
    return {
      'auth': auth,
      if (body!['channel_data'] != null) 'channel_data': body['channel_data'],
      if (body['shared_secret'] != null) 'shared_secret': body['shared_secret'],
    };
  };
}
