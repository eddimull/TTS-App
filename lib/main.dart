import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'app.dart';
import 'core/config/router.dart';
import 'core/storage/route_storage.dart';
import 'features/bookings/data/bookings_cache_storage.dart';
import 'features/media/data/upload_queue_storage.dart';
import 'features/notifications/data/push_payload.dart';
import 'firebase_options.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

// Don't retry on definitive server errors (4xx). Only retry on network
// failures or 5xx where a retry might succeed.
Duration? _retryPolicy(int retryCount, Object error) {
  if (error is DioException && error.response != null) return null;
  // Exponential backoff: 200ms, 400ms, 800ms, …
  return Duration(milliseconds: 200 * (1 << retryCount));
}

/// Shell prefixes that are valid initial locations after a cold-start restore.
/// Must stay aligned with `_kShellPrefixes` in `core/config/router.dart`.
const _kRestorableShellPrefixes = [
  '/dashboard',
  '/search',
  '/bookings',
  '/library',
  '/more',
  '/band-settings',
  '/finances',
];

/// Read the saved last-route synchronously and decide the initial location.
/// Returns `/welcome` when there's nothing recent to restore — the router's
/// auth/band guards route forward from there (an authenticated user is bounced
/// straight to their dashboard, a logged-out user sees the welcome showcase).
String _resolveInitialLocation(RouteStorage rs) {
  final last = rs.readLastRoute();
  final ts = rs.readLastRouteTimestamp();
  if (last == null || ts == null) return '/welcome';
  if (DateTime.now().difference(ts).inHours >= 24) return '/welcome';
  if (!_kRestorableShellPrefixes.any((p) => last.startsWith(p))) {
    return '/welcome';
  }
  return last;
}

/// Background/terminated push handler. Must be a top-level function — FCM
/// runs it in a separate background isolate, so it cannot touch app state,
/// Riverpod, or [PushService]'s instance state (no suppression check is
/// needed here either: the app is backgrounded, so there's no open thread to
/// suppress against).
///
/// Hybrid pushes (event reminders, band updates) carry a `notification`
/// block and are rendered by the OS automatically. Chat pushes are
/// data-only (see `PushPayload`/backend contract), so without this handler a
/// backgrounded/terminated Android device shows nothing for an incoming chat
/// message. [buildBackgroundNotification] is the isolate-safe pure mapper;
/// this function does the minimal plugin init + show.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  if (message.notification != null) return; // OS already rendered it
  final spec = buildBackgroundNotification(message.data);
  if (spec == null) return;

  final local = FlutterLocalNotificationsPlugin();
  await local.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  ));
  await local
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(AndroidNotificationChannel(
        spec.channelId,
        spec.channelName,
        description: spec.channelDescription,
        importance: Importance.high,
      ));
  await local.show(
    spec.id,
    spec.title,
    spec.body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        spec.channelId,
        spec.channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  // Set tz.local to the device's real zone so zoned notification scheduling
  // computes correct fire times. Without this, tz.local stays UTC. Best-effort:
  // fall back to UTC if the platform can't report a zone (e.g. desktop/web).
  try {
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
  } catch (_) {
    // Leave tz.local as the default (UTC); scheduling still resolves absolute
    // instants correctly for local-kind DateTimes.
  }

  // Pre-resolve SharedPreferences so the router can read the last route
  // synchronously at construction time — no race between restore and the
  // user's first interaction.
  final prefs = await SharedPreferences.getInstance();
  final routeStorage = RouteStorage(prefs);
  final bookingsCacheStorage = BookingsCacheStorage(prefs);
  final uploadQueueStorage = UploadQueueStorage(prefs);
  final initialLocation = _resolveInitialLocation(routeStorage);

  // Push notifications are only supported on iOS/Android. Guard so the Linux
  // desktop and web builds launch without a Firebase configuration.
  final pushSupported = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  if (pushSupported) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN');
      options.environment = const String.fromEnvironment(
        'SENTRY_ENVIRONMENT',
        defaultValue: 'development',
      );
      options.tracesSampleRate = 1.0;
      options.profilesSampleRate = 1.0;
      options.attachScreenshot = true;
      options.attachViewHierarchy = true;
    },
    appRunner: () => runApp(
      ProviderScope(
        retry: _retryPolicy,
        overrides: [
          routeStorageProvider.overrideWith((_) async => routeStorage),
          bookingsCacheStorageProvider.overrideWithValue(bookingsCacheStorage),
          uploadQueueStorageProvider.overrideWithValue(uploadQueueStorage),
          initialLocationProvider.overrideWithValue(initialLocation),
        ],
        child: const BandmateApp(),
      ),
    ),
  );
}
