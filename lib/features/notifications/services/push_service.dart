import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/notification_text.dart';
import '../data/push_payload.dart';

/// True only on platforms where FCM is supported.
bool get _pushSupported =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// Renders the body for a payload.
String renderBody(PushPayload p) => buildReminderBody(
      venue: p.venueAddress,
      firstItemTitle: p.firstItemTitle,
      firstItemTime: p.firstItemTime,
      showTime: p.showTime,
    );

/// Thin wrapper over FCM + local notifications. Logic-free where possible.
class PushService {
  PushService(this._local);

  final FlutterLocalNotificationsPlugin _local;

  static const _channel = AndroidNotificationChannel(
    'event_reminders',
    'Event Reminders',
    description: 'Reminders about events you are playing today',
    importance: Importance.high,
  );

  /// Initialize local-notification plugin + Android channel. Safe to call on
  /// unsupported platforms (no-op).
  Future<void> init() async {
    if (!_pushSupported) return;
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _local.initialize(initSettings);
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  /// Request notification permission from the OS. No-op on unsupported.
  Future<void> requestPermission() async {
    if (!_pushSupported) return;
    await FirebaseMessaging.instance.requestPermission();
  }

  /// Current FCM token, or null if unsupported/unavailable.
  Future<String?> token() async {
    if (!_pushSupported) return null;
    return FirebaseMessaging.instance.getToken();
  }

  /// Stream of token refreshes (empty stream on unsupported platforms).
  Stream<String> get onTokenRefresh =>
      _pushSupported ? FirebaseMessaging.instance.onTokenRefresh : const Stream.empty();

  bool _listening = false;

  /// Wire foreground message handling. Idempotent — repeated calls (e.g. a
  /// second login in the same process) do not attach duplicate listeners.
  void listenForeground() {
    if (!_pushSupported || _listening) return;
    _listening = true;
    FirebaseMessaging.onMessage.listen(_show);
  }

  Future<void> _show(RemoteMessage message) async {
    // Messages that carry a `notification` block are rendered by the OS itself
    // while foregrounded (notably on Android). Only manually render data-only
    // messages, otherwise the user sees the same reminder twice. The backend
    // contract for this feature is therefore: send DATA-ONLY messages.
    if (message.notification != null) return;
    final payload = PushPayload.fromData(message.data);
    final title = message.data['title']?.toString() ?? 'Event today';
    await _local.show(
      payload.notificationId,
      title,
      renderBody(payload),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'event_reminders',
          'Event Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Schedule a local notification to fire at [when] (a local wall-clock time).
  /// No-op on unsupported platforms.
  Future<void> scheduleLocal({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_pushSupported) return;
    final scheduled = tz.TZDateTime.from(when, tz.local);
    await _local.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'event_reminders',
          'Event Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancel a previously scheduled local notification by id. No-op on
  /// unsupported platforms.
  Future<void> cancelLocal(int id) async {
    if (!_pushSupported) return;
    await _local.cancel(id);
  }
}
