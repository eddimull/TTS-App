import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import 'api_response_cache.dart';
import 'deadline_adapter.dart';
import 'dev_tls.dart';
import 'offline_interceptor.dart';
import 'reachability.dart';
import '../storage/secure_storage.dart';
import 'api_endpoints.dart';
import '../../shared/providers/selected_band_provider.dart';

/// A callback invoked when the server returns 401. Typically used to navigate
/// to the login screen without requiring a BuildContext here.
typedef OnUnauthorized = void Function();

/// Key used in [RequestOptions.extra] to mark a request that has already been
/// retried after a token refresh, preventing infinite retry loops.
const _retriedAfterRefreshKey = '__retried_after_refresh';

/// Hard ceiling on how long an ordinary request may spend getting response
/// headers back, covering DNS, connect, TLS and time-to-first-byte. See
/// [DeadlineHttpClientAdapter] for why `connectTimeout` alone isn't enough.
///
/// Set slightly above `connectTimeout` so Dio's own, better-typed timeout
/// normally fires first and this stays a backstop for what it can't see.
const Duration kRequestDeadline = Duration(seconds: 10);

/// The same ceiling for multipart uploads, which legitimately take longer:
/// `fetch` doesn't complete until the whole body has gone out.
const Duration kUploadDeadline = Duration(minutes: 5);

class ApiClient {
  ApiClient({
    required SecureStorage storage,
    String? bandId,
    OnUnauthorized? onUnauthorized,
    Reachability? reachability,
    ApiResponseCache? cache,
  })  : _storage = storage,
        _bandId = bandId,
        _onUnauthorized = onUnauthorized,
        _reachability = reachability,
        _cache = cache {
    _dio = _buildDio();
  }

  final SecureStorage _storage;
  final String? _bandId;
  final OnUnauthorized? _onUnauthorized;
  final Reachability? _reachability;
  final ApiResponseCache? _cache;
  late final Dio _dio;

  Dio get dio => _dio;

  /// Cheap unauthenticated round trip used to find out whether the server has
  /// become reachable again, without waiting for the user to trigger a real
  /// request. Any HTTP answer — including a 404 — proves reachability.
  ///
  /// Hits the site root rather than an API endpoint on purpose: an
  /// authenticated probe that came back 401 would trip the interceptor below
  /// and sign the user out.
  Future<void> probeReachability() async {
    try {
      await _dio.head<dynamic>(
        '/',
        options: Options(
          extra: const {
            kProbeRequestKey: true,
            kRequestDeadlineKey: Duration(seconds: 5),
          },
          validateStatus: (_) => true,
        ),
      );
    } catch (_) {
      // The interceptor has already recorded the outcome; nothing to report.
    }
  }

  Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        connectTimeout: const Duration(seconds: 8),
        // Dio applies this between chunks, not to the whole download, so it
        // stays generous for large payloads on a slow connection.
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    // Debug-only: trust the local HTTPS dev server's self-signed cert. No-op on
    // web and in release builds. See dev_tls.dart.
    configureDevTls(dio);

    // After configureDevTls, which replaces the adapter outright.
    dio.httpClientAdapter = DeadlineHttpClientAdapter(
      dio.httpClientAdapter,
      deadline: kRequestDeadline,
      uploadDeadline: kUploadDeadline,
    );

    // First in the chain: it decides whether a request is worth sending at all
    // and, on the way back, whether a failure can be answered from disk.
    final reachability = _reachability;
    if (reachability != null) {
      dio.interceptors.add(
        OfflineInterceptor(
          reachability: reachability,
          cache: _cache,
          bandId: _bandId,
        ),
      );
    }

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.readToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          if (_bandId != null) {
            options.headers['X-Band-ID'] = _bandId;
          }

          handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode;

          if (status == 401) {
            await _storage.deleteToken();
            await _storage.deleteBandId();
            _onUnauthorized?.call();
            handler.next(error);
            return;
          }

          // Reactively refresh a stale token: EnsureUserInBand returns this
          // exact message when the token lacks an ability the user actually has
          // (e.g. right after going solo). Refresh once, retry once.
          final data = error.response?.data;
          final isStaleTokenError = status == 403 &&
              data is Map &&
              data['message'] == 'Insufficient token permissions.';

          final req = error.requestOptions;
          final alreadyRetried = req.extra[_retriedAfterRefreshKey] == true;
          final isRefreshCall = req.path == ApiEndpoints.mobileTokenRefresh;

          // Single-flight is intentionally NOT enforced: if several requests
          // hit this 403 at once they each refresh. That's safe for this app's
          // low-concurrency mobile usage (the trigger is the brief post-goSolo
          // window). Revisit with a refresh lock only if 401-after-refresh
          // reports appear.
          if (isStaleTokenError && !alreadyRetried && !isRefreshCall) {
            try {
              final refreshed = await _dio.post<Map<String, dynamic>>(
                ApiEndpoints.mobileTokenRefresh,
              );
              final newToken = refreshed.data?['token'] as String?;
              if (newToken != null) {
                await _storage.writeToken(newToken);

                // Re-fire the original request. onRequest attaches the new token
                // from storage. Mark it so a second 403 can't loop.
                final retryOptions = req.copyWith(
                  extra: {...req.extra, _retriedAfterRefreshKey: true},
                );
                final retryResponse = await _dio.fetch<dynamic>(retryOptions);
                handler.resolve(retryResponse);
                return;
              }
            } catch (_) {
              // Fall through to surfacing the original error.
            }
          }

          handler.next(error);
        },
      ),
    );

    return dio;
  }
}

/// Simple provider — the [OnUnauthorized] callback is wired up in [app.dart]
/// using a navigator key after the widget tree is ready.
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final bandId = ref.watch(selectedBandProvider).asData?.value?.toString();
  return ApiClient(
    storage: storage,
    bandId: bandId,
    // Both outlive this provider, which is rebuilt on every band switch: the
    // circuit breaker must not forget it is offline just because the user
    // changed bands, and the disk cache is a single shared store.
    reachability: ref.watch(reachabilityProvider),
    cache: ref.watch(apiResponseCacheProvider),
  );
});
