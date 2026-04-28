import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/config/router.dart';
import 'core/storage/route_storage.dart';

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
/// Returns `/login` when there's nothing recent to restore — auth/band guards
/// in the router will route forward from there.
String _resolveInitialLocation(RouteStorage rs) {
  final last = rs.readLastRoute();
  final ts = rs.readLastRouteTimestamp();
  if (last == null || ts == null) return '/login';
  if (DateTime.now().difference(ts).inHours >= 24) return '/login';
  if (!_kRestorableShellPrefixes.any((p) => last.startsWith(p))) return '/login';
  return last;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-resolve SharedPreferences so the router can read the last route
  // synchronously at construction time — no race between restore and the
  // user's first interaction.
  final prefs = await SharedPreferences.getInstance();
  final routeStorage = RouteStorage(prefs);
  final initialLocation = _resolveInitialLocation(routeStorage);

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
          initialLocationProvider.overrideWithValue(initialLocation),
        ],
        child: const BandmateApp(),
      ),
    ),
  );
}
