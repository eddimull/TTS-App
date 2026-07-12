import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/notification_channels.dart';
import '../data/notification_text.dart';
import '../data/push_payload.dart';
import '../data/push_route.dart';
import 'enrichment_service.dart' show LocalScheduler;

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

/// True when a chat-message push should be suppressed because its thread is
/// already open on screen (the live channel already shows the message, so a
/// local notification would be redundant). Pure and side-effect free so the
/// suppression rule can be unit-tested without a real FCM/plugin stack.
bool shouldSuppressChatPush(
  PushPayload payload,
  int? Function()? currentOpenConversation,
) =>
    payload.type == PushType.chatMessage &&
    payload.conversationId != null &&
    currentOpenConversation?.call()?.toString() == payload.conversationId;

/// Thin wrapper over FCM + local notifications. Logic-free where possible.
class PushService implements LocalScheduler {
  PushService(this._local);

  final FlutterLocalNotificationsPlugin _local;

  /// Optional callback invoked for `event_departure` data pushes so the
  /// provider layer can run location enrichment. Set during app init.
  Future<void> Function(PushPayload payload)? onDeparturePush;

  /// Returns the conversation id of the chat thread currently on screen, or
  /// null when none is open. Set by the provider layer (backed by
  /// `activeChatConversationProvider`); used to suppress a chat notification
  /// when its thread is already open. Route-string matching does not work
  /// here because the thread screen is reached via an imperative
  /// `context.push`, which is not reflected in the router's
  /// `currentConfiguration`.
  int? Function()? currentOpenConversation;

  /// Invoked when the user taps a locally-rendered notification (foreground
  /// tap callback, or a cold-start launch resolved in [init] via
  /// `getNotificationAppLaunchDetails`) that carries a route payload. Set by
  /// the provider layer to the same router.go used by [listenTaps] for
  /// OS-rendered (hybrid) pushes.
  void Function(String route)? onLocalTap;

  static const _channel = AndroidNotificationChannel(
    'event_reminders',
    'Event Reminders',
    description: 'Reminders about events you are playing today',
    importance: Importance.high,
  );

  static const _bandUpdatesChannel = AndroidNotificationChannel(
    BandUpdatesChannel.id,
    BandUpdatesChannel.name,
    description: BandUpdatesChannel.description,
    importance: Importance.high,
  );

  /// Initialize local-notification plugin + Android channel. Safe to call on
  /// unsupported platforms (no-op).
  ///
  /// Also wires tap handling for locally-rendered (data-only chat) pushes:
  /// - Foreground/running-app taps arrive via `onDidReceiveNotificationResponse`.
  /// - Terminated/cold-start taps are resolved here via
  ///   `getNotificationAppLaunchDetails`, mirroring the `getInitialMessage`
  ///   idiom [listenTaps] uses for OS-rendered pushes.
  Future<void> init() async {
    if (!_pushSupported) return;
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: handleLocalNotificationResponse,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_bandUpdatesChannel);

    final launchDetails = await _local.getNotificationAppLaunchDetails();
    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchPayload != null &&
        launchPayload.isNotEmpty) {
      onLocalTap?.call(launchPayload);
    }
  }

  /// Tap callback for locally-rendered notifications while the app process is
  /// alive (foreground or backgrounded-but-not-terminated). Public + static
  /// signature so it can be unit-tested by constructing a
  /// [NotificationResponse] directly, without going through the plugin.
  void handleLocalNotificationResponse(NotificationResponse response) {
    final route = response.payload;
    if (route != null && route.isNotEmpty) {
      onLocalTap?.call(route);
    }
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

  bool _tapsListening = false;

  /// Wire tap-to-open for OS-rendered (hybrid) pushes: background taps arrive
  /// via onMessageOpenedApp, terminated-state taps via getInitialMessage.
  /// Idempotent like [listenForeground].
  void listenTaps(void Function(String route) onRoute) {
    if (!_pushSupported || _tapsListening) return;
    _tapsListening = true;

    void handle(RemoteMessage message) {
      final route = routeForPushData(message.data);
      if (route != null) onRoute(route);
    }

    FirebaseMessaging.onMessageOpenedApp.listen(handle);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) handle(message);
    });
  }

  Future<void> _show(RemoteMessage message) async {
    // Messages carrying a `notification` block are OS-rendered when the app is
    // backgrounded/terminated, so we skip them here to avoid a double
    // notification; band-update pushes are sent this way (hybrid
    // notification+data). Data-only messages (leave-by reminders) have no
    // `notification` block and are rendered locally below.
    if (message.notification != null) return;
    final payload = PushPayload.fromData(message.data);
    if (shouldSuppressChatPush(payload, currentOpenConversation)) {
      return; // thread is open — the live channel already shows the message
    }
    if (payload.type == PushType.departure) {
      final cb = onDeparturePush;
      if (cb != null) {
        await cb(payload);
        return;
      }
    }
    final isReminder =
        payload.type == PushType.reminder8h || payload.type == PushType.departure;
    final title = payload.title ??
        (isReminder ? 'Event today' : 'TTS Bandmate');
    final body = isReminder
        ? renderBody(payload)
        : (payload.body ?? renderBody(payload));
    final android = isReminder
        ? const AndroidNotificationDetails(
            'event_reminders',
            'Event Reminders',
            importance: Importance.high,
            priority: Priority.high,
          )
        : const AndroidNotificationDetails(
            BandUpdatesChannel.id,
            BandUpdatesChannel.name,
            importance: Importance.high,
            priority: Priority.high,
          );
    await _local.show(
      payload.notificationId,
      title,
      body,
      NotificationDetails(
        android: android,
        iOS: const DarwinNotificationDetails(),
      ),
      payload: routeForPushData(message.data),
    );
  }

  /// Schedule a local notification to fire at [when] (a local wall-clock time).
  /// No-op on unsupported platforms.
  @override
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
  @override
  Future<void> cancelLocal(int id) async {
    if (!_pushSupported) return;
    await _local.cancel(id);
  }
}
