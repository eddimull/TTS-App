import 'package:dio/dio.dart';

import '../config/app_config.dart';

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
    ),
  );

  return (String channelName, String socketId, dynamic options) async {
    final res = await dio.post<Map<String, dynamic>>(
      '/broadcasting/auth',
      data: {
        'socket_id': socketId,
        'channel_name': channelName,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final body = res.data ?? const <String, dynamic>{};
    // Laravel returns { "auth": "key:signature" } for private channels and adds
    // "channel_data" for presence channels. Pass through whatever it returned so
    // the native SDK can complete the subscription.
    return {
      'auth': body['auth'],
      if (body['channel_data'] != null) 'channel_data': body['channel_data'],
      if (body['shared_secret'] != null) 'shared_secret': body['shared_secret'],
    };
  };
}
