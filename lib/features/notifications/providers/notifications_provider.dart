import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/device_repository.dart';
import '../services/push_service.dart';

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository(ref.watch(apiClientProvider).dio);
});

final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(FlutterLocalNotificationsPlugin());
});

/// Platform string the backend expects, or null when push is unsupported.
String? _platformName() {
  if (kIsWeb) return null;
  if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
  if (defaultTargetPlatform == TargetPlatform.android) return 'android';
  return null;
}

/// Coordinates token lifecycle: call [registerCurrentToken] after login and
/// [deregisterCurrentToken] on logout.
class PushRegistrar {
  PushRegistrar(this._ref);
  final Ref _ref;

  bool _watchingRefresh = false;

  Future<void> registerCurrentToken() async {
    final platform = _platformName();
    if (platform == null) return; // unsupported platform: no-op
    final push = _ref.read(pushServiceProvider);
    await push.init();
    await push.requestPermission();
    push.listenForeground();
    _watchTokenRefresh(push, platform);
    final token = await push.token();
    if (token == null) return;
    await _ref.read(deviceRepositoryProvider).register(
          token: token,
          platform: platform,
        );
  }

  /// Re-register with the backend when FCM rotates the token (reinstall,
  /// restore, periodic refresh), so the "safety net" push never silently
  /// breaks. Idempotent: only one subscription per process.
  void _watchTokenRefresh(PushService push, String platform) {
    if (_watchingRefresh) return;
    _watchingRefresh = true;
    push.onTokenRefresh.listen((token) async {
      try {
        await _ref.read(deviceRepositoryProvider).register(
              token: token,
              platform: platform,
            );
      } catch (_) {
        // Best-effort; the next login re-registers anyway.
      }
    });
  }

  Future<void> deregisterCurrentToken() async {
    if (_platformName() == null) return;
    final push = _ref.read(pushServiceProvider);
    final token = await push.token();
    if (token == null) return;
    try {
      await _ref.read(deviceRepositoryProvider).deregister(token);
    } catch (_) {
      // Best-effort: logout should not fail if deregistration does.
    }
  }
}

final pushRegistrarProvider = Provider<PushRegistrar>((ref) {
  return PushRegistrar(ref);
});
