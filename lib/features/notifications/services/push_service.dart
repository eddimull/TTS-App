import 'dart:async' show unawaited;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, MissingPluginException, PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/notification_channels.dart';
import '../data/notification_text.dart';
import '../data/push_payload.dart';
import '../data/push_route.dart';
import 'enrichment_service.dart' show LocalScheduler;

/// Breadcrumb for a notification tap. Taps were dropped silently on iOS for
/// months (no UNUserNotificationCenter delegate under the UIScene lifecycle)
/// with zero telemetry to show it — leave a trail per tap source so Sentry
/// can confirm which paths fire and what route each resolved. Best-effort.
void _tapBreadcrumb(String source, String? route) {
  unawaited(Sentry.addBreadcrumb(Breadcrumb(
    category: 'push.tap',
    message: route ?? '(no route)',
    data: {'source': source},
  )));
}

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

/// Id to render a local notification under. Android identifies notifications
/// by the (tag, id) PAIR, and the backend's FCM-rendered chat pushes occupy
/// (`chat_<conversationId>`, 0) — so chat renders locally under id 0 there too,
/// or the same conversation would hold two tray entries and cancel-by-tag
/// would miss one. iOS has no tags, so chat keeps the per-thread hash id
/// (id 0 for every thread would make different conversations replace each
/// other).
int localNotificationId(PushPayload payload, {required bool isAndroid}) =>
    isAndroid &&
            payload.type == PushType.chatMessage &&
            payload.conversationId != null
        ? 0
        : payload.notificationId;

/// True for hybrid (notification+data) push types that should still be
/// rendered locally while the app is in the FOREGROUND, where the OS shows
/// nothing for the `notification` block. Chat and questionnaire pushes are
/// sent hybrid so iOS delivers them when backgrounded (a data-only push
/// without APNs content-available is silently dropped); their data map
/// duplicates title/body so the local render needs nothing from the
/// `notification` block. Pure so the rule is unit-testable.
bool isForegroundRenderable(PushPayload payload) =>
    payload.type == PushType.chatMessage ||
    payload.type == PushType.questionnaireSubmitted;

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

  /// Invoked (instead of rendering) when a chat push is suppressed because
  /// its thread is open on screen. Right after an app resume the thread's
  /// realtime channel can still be dead/reconnecting, so the push may carry a
  /// message the channel never delivered — the provider layer refreshes the
  /// open thread rather than trusting the channel to have shown it.
  void Function(String conversationId)? onChatPushSuppressed;

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
    if (launchDetails?.didNotificationLaunchApp == true) {
      _tapBreadcrumb('local_launch', launchPayload);
    }
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
    _tapBreadcrumb('local_tap', route);
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
    // On iOS an FCM token cannot exist until APNs has delivered its device
    // token to the SDK; getToken() before that throws apns-token-not-set.
    // APNs registration races the post-login call path, so poll briefly
    // instead of failing the one registration attempt. onTokenRefresh remains
    // the safety net if APNs takes longer than this window.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      for (var attempt = 0; attempt < 10; attempt++) {
        final apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns != null) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
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
    FirebaseMessaging.onMessage.listen(handleForegroundMessage);
  }

  bool _tapsListening = false;

  /// Wire tap-to-open for OS-rendered (hybrid) pushes: background taps arrive
  /// via onMessageOpenedApp, terminated-state taps via getInitialMessage.
  /// Idempotent like [listenForeground].
  void listenTaps(void Function(String route) onRoute) {
    if (!_pushSupported || _tapsListening) return;
    _tapsListening = true;

    void handle(String source, RemoteMessage message) {
      final route = routeForPushData(message.data);
      _tapBreadcrumb(source, route);
      if (route != null) onRoute(route);
    }

    FirebaseMessaging.onMessageOpenedApp
        .listen((message) => handle('fcm_opened_app', message));
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) handle('fcm_initial_message', message);
    });
  }

  /// iOS-only side channel for the notification tap that launched the app
  /// from a terminated state. Under the UIScene lifecycle firebase_messaging
  /// never gathers its initial notification (its DidFinishLaunching observer
  /// registers too late to ever fire), so `getInitialMessage()` NEVER
  /// resolves; the plugin instead fires `onMessageOpenedApp` during launch,
  /// before [listenTaps] has attached a listener, and the event is dropped.
  /// The AppDelegate stashes the tap's userInfo natively and this channel
  /// pulls it once the Dart side is ready — same pull semantics that make the
  /// Android cold-start path (getInitialMessage) work.
  static const _launchChannel = MethodChannel('tts.band/launch_notification');

  /// Pull-and-clear the natively stashed cold-start tap, routing it like any
  /// other tap. Safe everywhere: Android and old binaries have no channel
  /// (MissingPluginException) and that must never break startup.
  Future<void> consumeLaunchNotification(
      void Function(String route) onRoute) async {
    Map<Object?, Object?>? data;
    try {
      data = await _launchChannel.invokeMethod<Map<Object?, Object?>>('get');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
    if (data == null) return;
    final route = routeForPushData(<String, dynamic>{
      for (final entry in data.entries)
        if (entry.key is String) entry.key as String: entry.value,
    });
    _tapBreadcrumb('ios_launch_stash', route);
    if (route != null) onRoute(route);
  }

  /// Handler for `FirebaseMessaging.onMessage` (foreground pushes). Public
  /// only so the suppression branch can be unit-tested with a hand-built
  /// [RemoteMessage].
  @visibleForTesting
  Future<void> handleForegroundMessage(RemoteMessage message) async {
    final payload = PushPayload.fromData(message.data);
    // Messages carrying a `notification` block are OS-rendered when the app is
    // backgrounded/terminated; in the foreground the OS shows nothing, so
    // chat/questionnaire hybrids are rendered locally below — chat
    // additionally suppressed when its thread is open. Other hybrid types
    // (band updates) stay foreground-silent for now, and skipping them here
    // avoids a double notification.
    if (message.notification != null && !isForegroundRenderable(payload)) {
      return;
    }
    if (shouldSuppressChatPush(payload, currentOpenConversation)) {
      // Thread is open — no tray notification, but the live channel may have
      // missed this message (dead socket right after resume), so let the
      // provider layer refresh the thread.
      onChatPushSuppressed?.call(payload.conversationId!);
      return;
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
    // Chat renders into the same per-conversation tray slot (tag) the backend
    // uses for OS-rendered hybrid pushes, so foreground- and background-
    // delivered messages replace each other and one cancel clears both.
    final chatTag = payload.type == PushType.chatMessage &&
            payload.conversationId != null
        ? chatNotificationTag(payload.conversationId!)
        : null;
    final android = isReminder
        ? const AndroidNotificationDetails(
            'event_reminders',
            'Event Reminders',
            importance: Importance.high,
            priority: Priority.high,
          )
        : AndroidNotificationDetails(
            BandUpdatesChannel.id,
            BandUpdatesChannel.name,
            importance: Importance.high,
            priority: Priority.high,
            tag: chatTag,
          );
    await _local.show(
      localNotificationId(payload,
          isAndroid: defaultTargetPlatform == TargetPlatform.android),
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

  /// Remove a conversation's notifications from the tray once its thread is
  /// on screen: the FCM-posted slot (tag `chat_<id>`, id 0 — Android renders
  /// backgrounded hybrid pushes natively under the backend-supplied tag) and
  /// the locally-rendered foreground slot. Without this, read messages sit in
  /// the tray until swiped, and 4+ stacked entries auto-group into a summary
  /// whose tap carries no deep link.
  Future<void> clearChatNotifications(String conversationId) async {
    if (!_pushSupported) return;
    // Best-effort: tray cleanup must never take down the thread screen, and
    // the plugin throws (not just errors) when its platform instance isn't
    // registered — e.g. init() failed, or a test environment.
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // FCM-rendered AND locally-rendered chat notifications both occupy
        // the (chat_<id>, 0) slot on Android — one cancel clears either.
        await _local.cancel(0, tag: chatNotificationTag(conversationId));
      } else {
        // iOS has no tags; foreground-rendered pushes use the hash id.
        await _local.cancel(chatNotificationId(conversationId));
      }
    } catch (_) {}
  }
}
